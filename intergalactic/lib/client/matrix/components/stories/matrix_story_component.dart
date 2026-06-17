import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/client/matrix/components/matrix_sync_listener.dart';
import 'package:intergalactic/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/image/lod_image.dart';
import 'package:intergalactic/utils/local_file.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixStoryComponent extends StoryComponent<MatrixClient>
    implements NeedsPostLoginInit, DisposableComponent {
  MatrixStoryComponent(super.client);

  static const int recentHistoryScanLimit = 120;
  static const Duration notificationMarkerRetention = Duration(days: 7);

  final StreamController<void> _storiesChanged = StreamController.broadcast();
  final Map<String, Map<String, StoryItem>> _storiesBySender = {};
  final Map<String, Map<String, StoryReaction>> _reactionsByStory = {};
  final Map<String, Map<String, StoryNotificationMarker>>
      _notificationMarkersByRoom = {};
  final Set<String> _roomsPendingInitialNotificationSuppressionScan = {};
  final Set<String> _notifiedStoryPostKeys = {};
  final Map<String, _StoryOutboxRecord> _outbox = {};
  final Set<String> _seenStoryKeys = {};
  bool _initialNotificationSuppressionScanComplete = false;
  int _pendingUploadCount = 0;
  Timer? _expiryTimer;

  @override
  Stream<void> get onStoriesChanged => _storiesChanged.stream;

  @override
  Map<String, List<StoryItem>> get activeStoriesByUser {
    _pruneExpiredStories(notify: false);
    return Map.unmodifiable({
      for (final entry in _storiesBySender.entries)
        entry.key: List<StoryItem>.unmodifiable(
          entry.value.values.toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        ),
    });
  }

  @override
  List<StoryItem> activeStoriesForUser(String userId) =>
      activeStoriesByUser[userId] ?? const [];

  @override
  bool hasUnseenStories(String userId) => activeStoriesForUser(
        userId,
      ).any((story) => !_seenStoryKeys.contains(story.seenKey));

  @override
  bool hasPendingStoryUpload(String userId) =>
      userId == client.matrixClient.userID && _pendingUploadCount > 0;

  @override
  Future<R> trackPendingStoryUpload<R>(Future<R> Function() action) async {
    _pendingUploadCount++;
    _storiesChanged.add(null);
    try {
      return await action();
    } finally {
      if (_pendingUploadCount > 0) {
        _pendingUploadCount--;
      }
      _storiesChanged.add(null);
    }
  }

  @override
  Map<String, List<StoryReaction>> get reactionsByStory => Map.unmodifiable({
        for (final entry in _reactionsByStory.entries)
          entry.key: List<StoryReaction>.unmodifiable(
            entry.value.values.toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
          ),
      });

  @override
  List<StoryReaction> reactionsForStory(StoryItem story) =>
      reactionsByStory[_storyReactionKey(story.senderId, story.storyId)] ??
      const [];

  @override
  StoryReaction? reactionForStoryByCurrentUser(StoryItem story) {
    final ownUserId = client.matrixClient.userID;
    if (ownUserId == null) {
      return null;
    }
    return _reactionsByStory[_storyReactionKey(story.senderId, story.storyId)]
        ?[ownUserId];
  }

  @override
  StoryNotificationSettings get notificationSettings {
    final content = client.matrixClient
        .accountData[storyNotificationSettingsAccountDataKey]?.content;
    return parseStoryNotificationSettingsContent(
      content == null ? null : Map<String, Object?>.from(content),
    );
  }

  @override
  bool storyReactionTargetsKnownStory(StoryReaction reaction) {
    if (super.storyReactionTargetsKnownStory(reaction)) {
      return true;
    }

    final now = DateTime.now().toUtc();
    final record = _outbox[reaction.storyId];
    if (record == null ||
        record.expiresAt.add(notificationMarkerRetention).isBefore(now)) {
      return false;
    }

    return record.recipients.any(
      (recipient) =>
          recipient.roomId == reaction.roomId &&
          recipient.eventId == reaction.storyEventId,
    );
  }

  @override
  Future<void> updateNotificationSettings(
    StoryNotificationSettings settings,
  ) async {
    final userId = client.matrixClient.userID;
    if (userId == null) {
      return;
    }

    await client.matrixClient.setAccountData(
      userId,
      storyNotificationSettingsAccountDataKey,
      settings.toJson(),
    );
    _storiesChanged.add(null);
  }

  @override
  int suppressedNotificationCountForRoom({
    required String roomId,
    required DateTime? latestOwnReceiptAt,
    required int rawNotificationCount,
  }) {
    final markers = _notificationMarkersByRoom[roomId]?.values;
    return countSuppressibleStoryNotifications(
      markers: markers ?? const <StoryNotificationMarker>[],
      latestOwnReceiptAt: latestOwnReceiptAt,
      rawNotificationCount: rawNotificationCount,
      initialScanPending:
          _roomsPendingInitialNotificationSuppressionScan.contains(roomId),
    );
  }

  @override
  void postLoginInit() {
    _loadViewedState();
    _loadOutbox();
    unawaited(_pruneOutbox(redactExpired: true));
    unawaited(refreshStories());
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _pruneExpiredStories();
      unawaited(_pruneOutbox(redactExpired: true));
    });
  }

  @override
  Future<void> refreshStories() async {
    final component = client.getComponent<DirectMessagesComponent>();
    final rooms = (component?.directMessageRooms.whereType<MatrixRoom>() ??
            const <MatrixRoom>[])
        .where(_isSendableStoryDm)
        .toList(growable: false);
    final initialSuppressionScan =
        !_initialNotificationSuppressionScanComplete && component != null;
    if (initialSuppressionScan) {
      _roomsPendingInitialNotificationSuppressionScan
        ..clear()
        ..addAll(rooms.map((room) => room.identifier));
    }

    var changed = false;
    try {
      for (final room in rooms) {
        var roomChanged = false;
        var roomWasPending = false;
        try {
          roomChanged = await _scanLocalRoomEvents(room);
          final result = await room.matrixRoom.searchEvents(
            searchFunc: (event) =>
                _isPlainStoryEventType(event.type) ||
                event.type == matrix.EventTypes.Encrypted,
            limit: recentHistoryScanLimit,
            includeEventTypes: {
              storyPhotoEventType,
              storyVideoEventType,
              storyReactionEventType,
              matrix.EventTypes.Encrypted,
            },
          );
          final resolvedEvents = <matrix.Event>[];
          for (final event in result.events) {
            final resolved = await _resolveStoryRelatedEvent(event);
            if (resolved == null) {
              continue;
            }
            resolvedEvents.add(resolved);
          }
          roomChanged =
              _addResolvedStoryEvents(room, resolvedEvents) || roomChanged;
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to refresh DM story history',
          );
        } finally {
          if (initialSuppressionScan) {
            roomWasPending = _roomsPendingInitialNotificationSuppressionScan
                .remove(room.identifier);
          }
        }

        if (roomChanged || roomWasPending) {
          room.notifyUpdate();
        }
        changed = roomChanged || changed;
      }
      changed = _pruneExpiredStories(notify: false) || changed;
      if (changed) {
        _storiesChanged.add(null);
      }
    } finally {
      if (initialSuppressionScan) {
        final remainingPendingRoomIds = Set<String>.of(
          _roomsPendingInitialNotificationSuppressionScan,
        );
        _roomsPendingInitialNotificationSuppressionScan.clear();
        _initialNotificationSuppressionScanComplete = true;
        for (final room in rooms) {
          if (remainingPendingRoomIds.contains(room.identifier)) {
            room.notifyUpdate();
          }
        }
      }
    }
  }

  Future<bool> _scanLocalRoomEvents(MatrixRoom room) async {
    final events = await client.matrixClient.database.getEventList(
      room.matrixRoom,
      start: 0,
      limit: recentHistoryScanLimit,
    );
    var changed = false;
    final resolvedEvents = <matrix.Event>[];
    for (final event in events) {
      final resolved = await _resolveStoryRelatedEvent(event);
      if (resolved == null) {
        continue;
      }
      resolvedEvents.add(resolved);
    }
    changed = _addResolvedStoryEvents(room, resolvedEvents) || changed;
    return changed;
  }

  Future<void> handleSyncEvent(
    MatrixRoom room,
    matrix.MatrixEvent matrixEvent,
  ) async {
    final component = client.getComponent<DirectMessagesComponent>();
    if (component?.isRoomDirectMessage(room) != true) {
      return;
    }

    final event = matrix.Event.fromMatrixEvent(matrixEvent, room.matrixRoom);
    if (event.type == matrix.EventTypes.Redaction) {
      if (_removeByEventId(event.redacts)) {
        room.notifyUpdate();
        _storiesChanged.add(null);
      }
      return;
    }

    final resolved = await _resolveStoryRelatedEvent(event);
    if (resolved == null) {
      return;
    }

    final changed = _addStoryRelatedEvent(room, resolved, notify: true);
    room.notifyUpdate();
    if (changed) {
      _storiesChanged.add(null);
    }
  }

  Future<matrix.Event?> _resolveStoryRelatedEvent(matrix.Event event) async {
    if (_isPlainStoryEventType(event.type)) {
      return event;
    }

    if (event.type != matrix.EventTypes.Encrypted) {
      return null;
    }

    try {
      final decrypted = await client.matrixClient.encryption?.decryptRoomEvent(
        event,
      );
      return decrypted != null && _isPlainStoryEventType(decrypted.type)
          ? decrypted
          : null;
    } catch (_) {
      return null;
    }
  }

  bool _isPlainStoryEventType(String eventType) =>
      eventType == storyPhotoEventType ||
      eventType == storyVideoEventType ||
      eventType == storyReactionEventType;

  bool _addStoryRelatedEvent(
    MatrixRoom room,
    matrix.Event event, {
    bool notify = false,
  }) {
    if (event.type == storyPhotoEventType ||
        event.type == storyVideoEventType) {
      return _addStoryFromEvent(room, event, notify: notify);
    }
    if (event.type == storyReactionEventType) {
      return _addReactionFromEvent(room, event, notify: notify);
    }
    return false;
  }

  bool _addResolvedStoryEvents(MatrixRoom room, List<matrix.Event> events) {
    var changed = false;
    for (final event in events.where(
      (event) =>
          event.type == storyPhotoEventType ||
          event.type == storyVideoEventType,
    )) {
      changed = _addStoryFromEvent(room, event) || changed;
    }
    for (final event
        in events.where((event) => event.type == storyReactionEventType)) {
      changed = _addReactionFromEvent(room, event) || changed;
    }
    return changed;
  }

  bool _addStoryFromEvent(
    MatrixRoom room,
    matrix.Event event, {
    bool notify = false,
  }) {
    if (event.redacted) {
      return _removeByEventId(event.eventId);
    }

    final content = _copyContent(event.content);
    final parsed = event.type == storyVideoEventType
        ? parseStoryVideoEventContent(content)
        : parseStoryEventContent(content);
    final notificationMarker = parsed ??
        (event.type == storyVideoEventType
            ? parseStoryVideoEventContent(content, allowExpired: true)
            : parseStoryEventContent(content, allowExpired: true));
    var changed = false;
    if (notificationMarker != null) {
      changed = _rememberNotificationMarker(room, event, notificationMarker);
    }

    if (parsed == null) {
      return changed;
    }

    final story = StoryItem(
      client: client,
      storyId: parsed.storyId,
      senderId: event.senderId,
      createdAt: parsed.createdAt,
      expiresAt: parsed.expiresAt,
      mediaUri: parsed.mediaUri,
      mediaType: parsed.mediaType,
      encrypted: parsed.encrypted,
      isOwn: event.senderId == client.matrixClient.userID,
      mimeType: parsed.mimeType,
      size: parsed.size,
      durationMs: parsed.durationMs,
      width: parsed.width,
      height: parsed.height,
      thumbnailUri: parsed.thumbnailUri,
      trimStartMs: parsed.trimStartMs,
      trimEndMs: parsed.trimEndMs,
      overlays: parsed.overlays,
      mentionedUserIds: parsed.mentionedUserIds,
      backgroundColor: parsed.backgroundColor,
      roomId: room.identifier,
      eventId: event.eventId,
      image: parsed.mediaType == StoryMediaType.image
          ? _MatrixStoryImageProvider(
              client: client.matrixClient,
              parsed: parsed,
            )
          : null,
      thumbnail: parsed.mediaType == StoryMediaType.video &&
              parsed.thumbnailUri != null
          ? _MatrixStoryImageProvider(
              client: client.matrixClient,
              parsed: parsed,
              thumbnail: true,
            )
          : null,
      video: parsed.mediaType == StoryMediaType.video
          ? _MatrixStoryVideoFileProvider(
              client: client.matrixClient,
              parsed: parsed,
            )
          : null,
      rawContent: parsed.content,
    );

    final stories = _storiesBySender.putIfAbsent(event.senderId, () => {});
    final existing = stories[story.storyId];
    if (existing?.eventId == story.eventId &&
        existing?.expiresAt == story.expiresAt) {
      return changed;
    }

    stories[story.storyId] = story;
    if (notify &&
        shouldNotifyForStoryPost(story) &&
        _rememberStoryPostNotification(story)) {
      unawaited(_notifyStoryPost(room, story));
    }
    return true;
  }

  bool _addReactionFromEvent(
    MatrixRoom room,
    matrix.Event event, {
    bool notify = false,
  }) {
    if (event.redacted) {
      return _removeReactionByEventId(event.eventId);
    }

    final parsed = parseStoryReactionEventContent(_copyContent(event.content));
    if (parsed == null || event.senderId == parsed.storySenderId) {
      return false;
    }
    if (!_reactionRoomLooksValid(room, parsed, event.senderId) ||
        !_isKnownReactionTarget(room, parsed)) {
      return false;
    }

    var changed = _rememberNotificationMarkerValue(
      room,
      StoryNotificationMarker(
        roomId: room.identifier,
        eventId: event.eventId,
        originServerTs: event.originServerTs.toUtc(),
        expiresAt: parsed.createdAt.add(storyLifetime),
      ),
    );

    final storyKey = _storyReactionKey(parsed.storySenderId, parsed.storyId);
    final reactions = _reactionsByStory.putIfAbsent(storyKey, () => {});
    final reaction = StoryReaction(
      roomId: room.identifier,
      eventId: event.eventId,
      storyId: parsed.storyId,
      storyEventId: parsed.storyEventId,
      storySenderId: parsed.storySenderId,
      reactorId: event.senderId,
      reaction: parsed.reaction,
      createdAt: parsed.createdAt,
      mentionedUserIds: parsed.mentionedUserIds,
    );
    final existing = reactions[event.senderId];
    if (existing?.eventId == reaction.eventId &&
        existing?.reaction == reaction.reaction) {
      return changed;
    }
    if (existing != null && !_isNewerStoryReaction(existing, reaction)) {
      return changed;
    }

    reactions[event.senderId] = reaction;
    if (notify && shouldNotifyForStoryReaction(reaction)) {
      unawaited(_notifyStoryReaction(room, reaction));
    }
    return true;
  }

  Future<void> _notifyStoryPost(MatrixRoom room, StoryItem story) async {
    try {
      final sender = room.getMemberOrFallback(story.senderId);
      await NotificationManager.notify(
        StoryNotificationContent(
          roomId: room.identifier,
          clientId: client.identifier,
          roomName: room.displayName,
          senderId: sender.identifier,
          senderName: sender.displayName,
          senderImage: sender.avatar,
          senderImageId: sender.avatarId,
          eventId: story.eventId ?? story.storyId,
          storySenderId: story.senderId,
          storyId: story.storyId,
          storyEventId: story.eventId,
          playSound: notificationSettings.sound,
          title: sender.displayName,
          content: 'Posted a story',
        ),
        forceShow: true,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to display story post notification',
      );
    }
  }

  Future<void> _notifyStoryReaction(
    MatrixRoom room,
    StoryReaction reaction,
  ) async {
    try {
      final reactor = room.getMemberOrFallback(reaction.reactorId);
      await NotificationManager.notify(
        StoryNotificationContent(
          roomId: room.identifier,
          clientId: client.identifier,
          roomName: room.displayName,
          senderId: reactor.identifier,
          senderName: reactor.displayName,
          senderImage: reactor.avatar,
          senderImageId: reactor.avatarId,
          eventId: reaction.eventId,
          storySenderId: reaction.storySenderId,
          storyId: reaction.storyId,
          storyEventId: reaction.storyEventId,
          playSound: notificationSettings.sound,
          title: reactor.displayName,
          content: 'Reacted to your story with ${reaction.reaction}',
        ),
        forceShow: true,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to display story reaction notification',
      );
    }
  }

  bool _reactionRoomLooksValid(
    MatrixRoom room,
    ParsedStoryReactionEvent parsed,
    String reactorId,
  ) {
    final participantIds = room.matrixRoom
        .getParticipants([matrix.Membership.join, matrix.Membership.invite])
        .map((user) => user.id)
        .toSet();
    final ownUserId = client.matrixClient.userID;
    if (ownUserId != null) {
      participantIds.add(ownUserId);
    }
    final directMessages = client.getComponent<DirectMessagesComponent>();
    final dmPartner = directMessages?.getDirectMessagePartnerId(room);
    if (dmPartner != null) {
      participantIds.add(dmPartner);
    }

    return participantIds.contains(parsed.storySenderId) &&
        participantIds.contains(reactorId);
  }

  bool _isKnownReactionTarget(
    MatrixRoom room,
    ParsedStoryReactionEvent parsed,
  ) {
    final now = DateTime.now().toUtc();
    final activeStory = _storiesBySender[parsed.storySenderId]?[parsed.storyId];
    if (activeStory != null &&
        activeStory.eventId == parsed.storyEventId &&
        activeStory.expiresAt.add(notificationMarkerRetention).isAfter(now)) {
      return true;
    }

    final record = _outbox[parsed.storyId];
    if (record == null ||
        record.expiresAt.add(notificationMarkerRetention).isBefore(now)) {
      return false;
    }
    return record.recipients.any(
      (recipient) =>
          recipient.roomId == room.identifier &&
          recipient.eventId == parsed.storyEventId,
    );
  }

  @override
  Future<void> sendStoryReaction(StoryItem story, String reaction) async {
    final ownUserId = client.matrixClient.userID;
    final roomId = story.roomId;
    final storyEventId = story.eventId;
    if (ownUserId == null ||
        story.isOwn ||
        roomId == null ||
        storyEventId == null ||
        !storyReactionChoices.contains(reaction)) {
      return;
    }

    final matrixRoom = client.matrixClient.getRoomById(roomId);
    final room = client.getRoom(roomId);
    if (matrixRoom == null || room is! MatrixRoom) {
      return;
    }

    final existing = reactionForStoryByCurrentUser(story);
    if (existing?.reaction == reaction) {
      return;
    }
    if (existing != null) {
      try {
        await matrixRoom.redactEvent(
          existing.eventId,
          reason: 'Inter Galactic story reaction replaced',
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to redact previous story reaction',
        );
        return;
      }
      _removeReactionByEventId(existing.eventId);
    }

    final createdAt = DateTime.now().toUtc();
    final content = <String, Object?>{
      'v': 1,
      'story_id': story.storyId,
      'story_event_id': storyEventId,
      'story_sender': story.senderId,
      'created_at': createdAt.millisecondsSinceEpoch,
      'reaction': reaction,
      'm.relates_to': {
        'rel_type': 'm.annotation',
        'event_id': storyEventId,
        'key': reaction,
      },
      'm.mentions': {
        'user_ids': [story.senderId],
      },
    };
    final eventId = await matrixRoom.sendEvent(
      Map<String, dynamic>.from(content),
      type: storyReactionEventType,
      displayPendingEvent: false,
    );
    if (eventId == null) {
      return;
    }

    final storyKey = _storyReactionKey(story.senderId, story.storyId);
    _reactionsByStory.putIfAbsent(storyKey, () => {})[ownUserId] =
        StoryReaction(
      roomId: room.identifier,
      eventId: eventId,
      storyId: story.storyId,
      storyEventId: storyEventId,
      storySenderId: story.senderId,
      reactorId: ownUserId,
      reaction: reaction,
      createdAt: createdAt,
      mentionedUserIds: [story.senderId],
    );
    _rememberNotificationMarkerValue(
      room,
      StoryNotificationMarker(
        roomId: room.identifier,
        eventId: eventId,
        originServerTs: createdAt,
        expiresAt: createdAt.add(storyLifetime),
      ),
    );
    room.notifyUpdate();
    _storiesChanged.add(null);
  }

  @override
  Future<StoryUploadResult> uploadPhotos(List<StoryPhotoUpload> photos) async {
    final targets = _targetRooms(eventType: storyPhotoEventType);
    if (targets.isEmpty || photos.isEmpty) {
      return StoryUploadResult(
        storyCount: 0,
        sentEventCount: 0,
        targetRoomCount: targets.length,
        failedEventCount: photos.length * targets.length,
      );
    }

    var storyCount = 0;
    var sentEventCount = 0;
    var failedEventCount = 0;

    for (final (index, photo) in photos.indexed) {
      final createdAt = DateTime.now().toUtc();
      final expiresAt = createdAt.add(storyLifetime);
      final storyId = client.matrixClient.generateUniqueTransactionId();
      final recipients = <_StoryRecipient>[];
      Map<String, Object?>? firstContent;

      for (final room in targets) {
        try {
          final sent = await _sendPhotoToRoom(
            room: room,
            photo: photo,
            storyId: storyId,
            createdAt: createdAt,
            expiresAt: expiresAt,
          );
          if (sent.eventId != null) {
            recipients.add(
              _StoryRecipient(roomId: room.identifier, eventId: sent.eventId!),
            );
            firstContent ??= sent.content;
            sentEventCount++;
          } else {
            failedEventCount++;
          }
        } catch (error, stackTrace) {
          failedEventCount++;
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to send story photo to a DM room',
          );
        }
      }

      if (recipients.isEmpty) {
        continue;
      }

      storyCount++;
      _outbox[storyId] = _StoryOutboxRecord(
        storyId: storyId,
        createdAt: createdAt,
        expiresAt: expiresAt,
        recipients: recipients,
        media: _mediaSummary(firstContent),
      );
      _storiesBySender.putIfAbsent(
        client.matrixClient.userID!,
        () => {},
      )[storyId] = StoryItem(
        client: client,
        storyId: storyId,
        senderId: client.matrixClient.userID!,
        createdAt: createdAt,
        expiresAt: expiresAt,
        mediaUri: _mediaUri(firstContent) ?? Uri.parse('mxc://local/$storyId'),
        encrypted: firstContent?['file'] is Map,
        isOwn: true,
        mentionedUserIds: photo.mentionedUserIds,
        roomId: recipients.first.roomId,
        eventId: recipients.first.eventId,
        image: MemoryImage(photo.bytes),
        rawContent: firstContent ?? const {},
      );
      if (index < photos.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    await _saveOutbox();
    _storiesChanged.add(null);
    return StoryUploadResult(
      storyCount: storyCount,
      sentEventCount: sentEventCount,
      targetRoomCount: targets.length,
      failedEventCount: failedEventCount,
    );
  }

  @override
  Future<StoryUploadResult> uploadVideos(List<StoryVideoUpload> videos) async {
    final targets = _targetRooms(eventType: storyVideoEventType);
    if (targets.isEmpty || videos.isEmpty) {
      return StoryUploadResult(
        storyCount: 0,
        sentEventCount: 0,
        targetRoomCount: targets.length,
        failedEventCount: videos.length * targets.length,
      );
    }

    var storyCount = 0;
    var sentEventCount = 0;
    var failedEventCount = 0;

    for (final (index, video) in videos.indexed) {
      final createdAt = DateTime.now().toUtc();
      final expiresAt = createdAt.add(storyLifetime);
      final storyId = client.matrixClient.generateUniqueTransactionId();
      final recipients = <_StoryRecipient>[];
      Map<String, Object?>? firstContent;

      for (final room in targets) {
        try {
          final sent = await _sendVideoToRoom(
            room: room,
            video: video,
            storyId: storyId,
            createdAt: createdAt,
            expiresAt: expiresAt,
          );
          if (sent.eventId != null) {
            recipients.add(
              _StoryRecipient(roomId: room.identifier, eventId: sent.eventId!),
            );
            firstContent ??= sent.content;
            sentEventCount++;
          } else {
            failedEventCount++;
          }
        } catch (error, stackTrace) {
          failedEventCount++;
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to send story video to a DM room',
          );
        }
      }

      if (recipients.isEmpty) {
        continue;
      }

      storyCount++;
      final parsedContent = firstContent == null
          ? null
          : parseStoryVideoEventContent(
              firstContent,
              now: createdAt,
              allowExpired: true,
            );
      _outbox[storyId] = _StoryOutboxRecord(
        storyId: storyId,
        createdAt: createdAt,
        expiresAt: expiresAt,
        recipients: recipients,
        media: _mediaSummary(firstContent),
      );
      _storiesBySender.putIfAbsent(
        client.matrixClient.userID!,
        () => {},
      )[storyId] = StoryItem(
        client: client,
        storyId: storyId,
        senderId: client.matrixClient.userID!,
        createdAt: createdAt,
        expiresAt: expiresAt,
        mediaUri: _mediaUri(firstContent) ?? Uri.parse('mxc://local/$storyId'),
        mediaType: StoryMediaType.video,
        encrypted: firstContent?['file'] is Map,
        isOwn: true,
        mimeType: video.mimeType,
        size: video.sizeBytes,
        durationMs: video.duration.inMilliseconds,
        width: video.width,
        height: video.height,
        trimStartMs: video.trimStart.inMilliseconds,
        trimEndMs: video.effectiveTrimEnd.inMilliseconds,
        overlays: video.overlays,
        mentionedUserIds: video.mentionedUserIds,
        backgroundColor: video.backgroundColor,
        roomId: recipients.first.roomId,
        eventId: recipients.first.eventId,
        thumbnail: video.thumbnailBytes == null
            ? null
            : MemoryImage(video.thumbnailBytes!),
        video: parsedContent == null
            ? SystemFileProvider(video.path)
            : _MatrixStoryVideoFileProvider(
                client: client.matrixClient,
                parsed: parsedContent,
              ),
        rawContent: firstContent ?? const {},
      );
      if (index < videos.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    await _saveOutbox();
    _storiesChanged.add(null);
    return StoryUploadResult(
      storyCount: storyCount,
      sentEventCount: sentEventCount,
      targetRoomCount: targets.length,
      failedEventCount: failedEventCount,
    );
  }

  Future<_StorySendResult> _sendPhotoToRoom({
    required MatrixRoom room,
    required StoryPhotoUpload photo,
    required String storyId,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) async {
    if (!storyImageSizeIsAllowed(photo.bytes.lengthInBytes)) {
      throw StateError('Story image exceeds Inter Galactic story size');
    }

    final file = await matrix.MatrixImageFile.create(
      bytes: photo.bytes,
      name: photo.name,
      mimeType: photo.mimeType,
      nativeImplementations: MatrixClient.nativeImplementations,
    );
    if (!storyImageSizeIsAllowed(file.size)) {
      throw StateError('Story image exceeds Inter Galactic story size');
    }

    final maxSize = client.maxFileSize;
    if (maxSize != null && file.size > maxSize) {
      throw StateError('Story image exceeds homeserver upload size');
    }

    matrix.MatrixFile uploadFile = file;
    matrix.EncryptedFile? encryptedFile;
    if (room.matrixRoom.encrypted &&
        client.matrixClient.fileEncryptionEnabled) {
      encryptedFile = await file.encrypt();
      uploadFile = encryptedFile.toMatrixFile();
    }

    final uploadUri = await client.matrixClient.uploadContent(
      uploadFile.bytes,
      filename: uploadFile.name,
      contentType: uploadFile.mimeType,
    );
    final mentionedUserIds =
        normalizeStoryMentionUserIds(photo.mentionedUserIds);
    final content = <String, Object?>{
      'v': 1,
      'story_id': storyId,
      'created_at': createdAt.millisecondsSinceEpoch,
      'expires_at': expiresAt.millisecondsSinceEpoch,
      'msgtype': matrix.MessageTypes.Image,
      'body': file.name,
      'filename': file.name,
      'm.mentions': {'user_ids': mentionedUserIds},
      if (encryptedFile == null) 'url': uploadUri.toString(),
      if (encryptedFile != null)
        'file': {
          'url': uploadUri.toString(),
          'mimetype': file.mimeType,
          'v': 'v2',
          'key': {
            'alg': 'A256CTR',
            'ext': true,
            'k': encryptedFile.k,
            'key_ops': ['encrypt', 'decrypt'],
            'kty': 'oct',
          },
          'iv': encryptedFile.iv,
          'hashes': {'sha256': encryptedFile.sha256},
        },
      'info': file.info,
    };

    final eventId = await room.matrixRoom.sendEvent(
      Map<String, dynamic>.from(content),
      type: storyPhotoEventType,
      displayPendingEvent: false,
    );
    return _StorySendResult(content: content, eventId: eventId);
  }

  Future<_StorySendResult> _sendVideoToRoom({
    required MatrixRoom room,
    required StoryVideoUpload video,
    required String storyId,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) async {
    if (!video.hasValidSelection || !video.usesFullSource) {
      throw StateError('Story video trim export is not available');
    }
    if (!storyVideoSizeIsAllowed(video.sizeBytes)) {
      throw StateError('Story video exceeds Inter Galactic story size');
    }

    final bytes = await readLocalFileBytes(video.path);
    if (bytes == null || !storyVideoSizeIsAllowed(bytes.lengthInBytes)) {
      throw StateError('Story video cannot be read or exceeds story size');
    }

    final file = matrix.MatrixVideoFile(
      bytes: bytes,
      name: video.name,
      mimeType: video.mimeType,
      width: video.width,
      height: video.height,
      duration: video.duration.inMilliseconds,
    );
    final maxSize = client.maxFileSize;
    if (maxSize != null && file.size > maxSize) {
      throw StateError('Story video exceeds homeserver upload size');
    }

    matrix.MatrixImageFile? thumbnailFile;
    if (video.thumbnailBytes != null && video.thumbnailBytes!.isNotEmpty) {
      thumbnailFile = await matrix.MatrixImageFile.create(
        bytes: video.thumbnailBytes!,
        name: '${video.name}.thumbnail',
        mimeType: video.thumbnailMimeType,
        nativeImplementations: MatrixClient.nativeImplementations,
      );
    }

    matrix.MatrixFile uploadFile = file;
    matrix.MatrixFile? uploadThumbnail = thumbnailFile;
    matrix.EncryptedFile? encryptedFile;
    matrix.EncryptedFile? encryptedThumbnail;
    if (room.matrixRoom.encrypted &&
        client.matrixClient.fileEncryptionEnabled) {
      encryptedFile = await file.encrypt();
      uploadFile = encryptedFile.toMatrixFile();
      if (thumbnailFile != null) {
        encryptedThumbnail = await thumbnailFile.encrypt();
        uploadThumbnail = encryptedThumbnail.toMatrixFile();
      }
    }

    final uploadUri = await client.matrixClient.uploadContent(
      uploadFile.bytes,
      filename: uploadFile.name,
      contentType: uploadFile.mimeType,
    );
    Uri? thumbnailUploadUri;
    if (uploadThumbnail != null) {
      thumbnailUploadUri = await client.matrixClient.uploadContent(
        uploadThumbnail.bytes,
        filename: uploadThumbnail.name,
        contentType: uploadThumbnail.mimeType,
      );
    }

    final mentionedUserIds =
        normalizeStoryMentionUserIds(video.mentionedUserIds);
    final content = <String, Object?>{
      'v': 1,
      'story_id': storyId,
      'media_type': StoryMediaType.video.jsonValue,
      'created_at': createdAt.millisecondsSinceEpoch,
      'expires_at': expiresAt.millisecondsSinceEpoch,
      'duration_ms': video.duration.inMilliseconds,
      'trim_start_ms': video.trimStart.inMilliseconds,
      'trim_end_ms': video.effectiveTrimEnd.inMilliseconds,
      'overlays': video.overlays.map((overlay) => overlay.toJson()).toList(),
      'background_color': video.backgroundColor,
      'msgtype': matrix.MessageTypes.Video,
      'body': file.name,
      'filename': file.name,
      'm.mentions': {'user_ids': mentionedUserIds},
      if (encryptedFile == null) 'url': uploadUri.toString(),
      if (encryptedFile != null)
        'file': {
          'url': uploadUri.toString(),
          'mimetype': file.mimeType,
          'v': 'v2',
          'key': {
            'alg': 'A256CTR',
            'ext': true,
            'k': encryptedFile.k,
            'key_ops': ['encrypt', 'decrypt'],
            'kty': 'oct',
          },
          'iv': encryptedFile.iv,
          'hashes': {'sha256': encryptedFile.sha256},
        },
      'info': {
        ...file.info,
        if (thumbnailFile != null && encryptedThumbnail == null)
          'thumbnail_url': thumbnailUploadUri.toString(),
        if (thumbnailFile != null && encryptedThumbnail != null)
          'thumbnail_file': {
            'url': thumbnailUploadUri.toString(),
            'mimetype': thumbnailFile.mimeType,
            'v': 'v2',
            'key': {
              'alg': 'A256CTR',
              'ext': true,
              'k': encryptedThumbnail.k,
              'key_ops': ['encrypt', 'decrypt'],
              'kty': 'oct',
            },
            'iv': encryptedThumbnail.iv,
            'hashes': {'sha256': encryptedThumbnail.sha256},
          },
        if (thumbnailFile != null) 'thumbnail_info': thumbnailFile.info,
      },
    };

    final eventId = await room.matrixRoom.sendEvent(
      Map<String, dynamic>.from(content),
      type: storyVideoEventType,
      displayPendingEvent: false,
    );
    return _StorySendResult(content: content, eventId: eventId);
  }

  @override
  Future<void> deleteStory(String storyId) async {
    final ownUserId = client.matrixClient.userID;
    if (ownUserId == null) {
      return;
    }

    final record = _outbox[storyId];
    final recipients = <_StoryRecipient>[
      if (record != null) ...record.recipients,
      ...(_storiesBySender[ownUserId]
              ?.values
              .where((story) => story.storyId == storyId)
              .map(
                (story) => _StoryRecipient(
                  roomId: story.roomId,
                  eventId: story.eventId,
                ),
              )
              .where(
                (recipient) =>
                    recipient.roomId != null && recipient.eventId != null,
              ) ??
          const <_StoryRecipient>[]),
    ];

    var hadFailure = false;
    for (final recipient in recipients) {
      final roomId = recipient.roomId;
      final eventId = recipient.eventId;
      if (roomId == null || eventId == null) {
        continue;
      }
      try {
        await client.matrixClient
            .getRoomById(roomId)
            ?.redactEvent(eventId, reason: 'Inter Galactic story deleted');
      } catch (error, stackTrace) {
        hadFailure = true;
        Log.onError(error, stackTrace, content: 'Failed to redact story event');
      }
    }

    if (!hadFailure) {
      _outbox.remove(storyId);
      _storiesBySender[ownUserId]?.remove(storyId);
      _reactionsByStory.remove(_storyReactionKey(ownUserId, storyId));
      await _saveOutbox();
      _storiesChanged.add(null);
    }
  }

  @override
  Future<void> markStoriesSeen(
    String userId,
    Iterable<StoryItem> stories,
  ) async {
    var changed = false;
    for (final story in stories) {
      changed = _seenStoryKeys.add(story.seenKey) || changed;
    }
    if (changed) {
      await _saveViewedState();
      _storiesChanged.add(null);
    }
  }

  List<MatrixRoom> _targetRooms({required String eventType}) {
    final component = client.getComponent<DirectMessagesComponent>();
    final rooms = component?.directMessageRooms.whereType<MatrixRoom>() ??
        const <MatrixRoom>[];
    return rooms
        .where((room) => _isSendableDm(room, eventType: eventType))
        .toList(growable: false);
  }

  bool _isSendableDm(
    MatrixRoom room, {
    String eventType = storyPhotoEventType,
  }) {
    final component = client.getComponent<DirectMessagesComponent>();
    if (component?.isRoomDirectMessage(room) != true) {
      return false;
    }
    final sendEventType =
        room.matrixRoom.encrypted ? matrix.EventTypes.Encrypted : eventType;
    return room.matrixRoom.canSendEvent(sendEventType);
  }

  bool _isSendableStoryDm(MatrixRoom room) {
    return _isSendableDm(room, eventType: storyPhotoEventType) ||
        _isSendableDm(room, eventType: storyVideoEventType);
  }

  void _loadViewedState() {
    final content =
        client.matrixClient.accountData[storyViewedAccountDataKey]?.content;
    final stories = content?['stories'];
    if (stories is List) {
      _seenStoryKeys
        ..clear()
        ..addAll(stories.whereType<String>());
    }
  }

  Future<void> _saveViewedState() async {
    await client.matrixClient.setAccountData(
      client.matrixClient.userID!,
      storyViewedAccountDataKey,
      {'v': 1, 'stories': _seenStoryKeys.toList(growable: false)},
    );
  }

  void _loadOutbox() {
    final content =
        client.matrixClient.accountData[storyOutboxAccountDataKey]?.content;
    final stories = content?['stories'];
    _outbox.clear();
    if (stories is! List) {
      return;
    }
    for (final raw in stories) {
      final record = _StoryOutboxRecord.fromJson(raw);
      if (record != null) {
        _outbox[record.storyId] = record;
      }
    }
  }

  Future<void> _saveOutbox() async {
    await client.matrixClient.setAccountData(
      client.matrixClient.userID!,
      storyOutboxAccountDataKey,
      {
        'v': 1,
        'stories': _outbox.values.map((record) => record.toJson()).toList(),
      },
    );
  }

  Future<void> _pruneOutbox({required bool redactExpired}) async {
    final now = DateTime.now().toUtc();
    final expired = _outbox.values
        .where((record) => !record.expiresAt.isAfter(now))
        .toList(growable: false);
    if (expired.isEmpty) {
      return;
    }

    for (final record in expired) {
      _outbox.remove(record.storyId);
      final ownUserId = client.matrixClient.userID;
      if (ownUserId != null) {
        _storiesBySender[ownUserId]?.remove(record.storyId);
      }
      if (!redactExpired) {
        continue;
      }
      for (final recipient in record.recipients) {
        if (recipient.roomId == null || recipient.eventId == null) {
          continue;
        }
        try {
          await client.matrixClient.getRoomById(recipient.roomId!)?.redactEvent(
                recipient.eventId!,
                reason: 'Inter Galactic story expired',
              );
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to redact expired story event',
          );
        }
      }
    }
    await _saveOutbox();
    _storiesChanged.add(null);
  }

  bool _pruneExpiredStories({bool notify = true}) {
    final now = DateTime.now().toUtc();
    var changed = false;
    for (final senderId in _storiesBySender.keys.toList()) {
      final stories = _storiesBySender[senderId]!;
      for (final entry in stories.entries.toList()) {
        final story = entry.value;
        if (!story.isExpired(now)) {
          continue;
        }
        stories.remove(entry.key);
        _notifiedStoryPostKeys.remove(_storyPostNotificationKey(story));
        changed = true;
      }
      if (stories.isEmpty) {
        _storiesBySender.remove(senderId);
      }
    }
    for (final storyKey in _reactionsByStory.keys.toList()) {
      final parts = storyKey.split('|');
      if (parts.length != 2 || _storiesBySender[parts[0]]?[parts[1]] == null) {
        _reactionsByStory.remove(storyKey);
        changed = true;
      }
    }
    changed = _pruneExpiredNotificationMarkers(now) || changed;
    if (changed && notify) {
      _storiesChanged.add(null);
    }
    return changed;
  }

  bool _removeByEventId(String? eventId) {
    if (eventId == null) {
      return false;
    }

    var changed = false;
    for (final senderId in _storiesBySender.keys.toList()) {
      final stories = _storiesBySender[senderId]!;
      final before = stories.length;
      stories.removeWhere((_, story) => story.eventId == eventId);
      if (stories.isEmpty) {
        _storiesBySender.remove(senderId);
      }
      changed = changed || before != stories.length;
    }
    changed = _removeNotificationMarkerByEventId(eventId) || changed;
    changed = _removeReactionByEventId(eventId) || changed;
    return changed;
  }

  bool _removeReactionByEventId(String? eventId) {
    if (eventId == null) {
      return false;
    }

    var changed = false;
    for (final storyKey in _reactionsByStory.keys.toList()) {
      final reactions = _reactionsByStory[storyKey]!;
      final before = reactions.length;
      reactions.removeWhere((_, reaction) => reaction.eventId == eventId);
      if (reactions.isEmpty) {
        _reactionsByStory.remove(storyKey);
      }
      changed = changed || before != reactions.length;
    }
    return changed;
  }

  Map<String, Object?> _copyContent(Map<String, dynamic> content) =>
      Map<String, Object?>.from(content);

  String _storyReactionKey(String storySenderId, String storyId) =>
      '$storySenderId|$storyId';

  bool _isNewerStoryReaction(
    StoryReaction existing,
    StoryReaction incoming,
  ) {
    if (incoming.createdAt.isAfter(existing.createdAt)) {
      return true;
    }
    if (incoming.createdAt.isBefore(existing.createdAt)) {
      return false;
    }
    return incoming.eventId.compareTo(existing.eventId) > 0;
  }

  bool _rememberStoryPostNotification(StoryItem story) =>
      _notifiedStoryPostKeys.add(_storyPostNotificationKey(story));

  String _storyPostNotificationKey(StoryItem story) =>
      storyPostNotificationDedupeKey(
        clientId: client.identifier,
        senderId: story.senderId,
        storyId: story.storyId,
      );

  bool _rememberNotificationMarker(
    MatrixRoom room,
    matrix.Event event,
    ParsedStoryEvent parsed,
  ) {
    return _rememberNotificationMarkerValue(
      room,
      StoryNotificationMarker(
        roomId: room.identifier,
        eventId: event.eventId,
        originServerTs: event.originServerTs.toUtc(),
        expiresAt: parsed.expiresAt,
      ),
    );
  }

  bool _rememberNotificationMarkerValue(
    MatrixRoom room,
    StoryNotificationMarker marker,
  ) {
    final roomMarkers = _notificationMarkersByRoom.putIfAbsent(
      room.identifier,
      () => {},
    );
    final existing = roomMarkers[marker.eventId];
    roomMarkers[marker.eventId] = marker;
    return existing?.originServerTs != marker.originServerTs ||
        existing?.expiresAt != marker.expiresAt;
  }

  bool _removeNotificationMarkerByEventId(String? eventId) {
    if (eventId == null) {
      return false;
    }

    var changed = false;
    for (final roomId in _notificationMarkersByRoom.keys.toList()) {
      final roomMarkers = _notificationMarkersByRoom[roomId]!;
      changed = roomMarkers.remove(eventId) != null || changed;
      if (roomMarkers.isEmpty) {
        _notificationMarkersByRoom.remove(roomId);
      }
    }
    return changed;
  }

  bool _pruneExpiredNotificationMarkers(DateTime now) {
    var changed = false;
    for (final roomId in _notificationMarkersByRoom.keys.toList()) {
      final roomMarkers = _notificationMarkersByRoom[roomId]!;
      final before = roomMarkers.length;
      roomMarkers.removeWhere(
        (_, marker) =>
            !marker.expiresAt.add(notificationMarkerRetention).isAfter(now),
      );
      if (roomMarkers.isEmpty) {
        _notificationMarkersByRoom.remove(roomId);
      }
      changed = changed || before != roomMarkers.length;
    }
    return changed;
  }

  Map<String, Object?> _mediaSummary(Map<String, Object?>? content) {
    final info = content?['info'];
    final file = content?['file'];
    return {
      'encrypted': file is Map,
      if (content?['url'] is String) 'url': content?['url'],
      if (file is Map && file['url'] is String) 'url': file['url'],
      if (info is Map) 'info': Map<String, Object?>.from(info),
    };
  }

  Uri? _mediaUri(Map<String, Object?>? content) {
    final direct = content?['url'];
    if (direct is String) {
      return Uri.tryParse(direct);
    }
    final file = content?['file'];
    if (file is Map && file['url'] is String) {
      return Uri.tryParse(file['url'] as String);
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    _expiryTimer?.cancel();
    await _storiesChanged.close();
  }
}

class _MatrixStoryVideoFileProvider implements FileProvider {
  _MatrixStoryVideoFileProvider({
    required this.client,
    required this.parsed,
  });

  final matrix.Client client;
  final ParsedStoryEvent parsed;

  @override
  String get fileIdentifier => _MatrixStoryMediaLoader.cacheIdentifier(parsed);

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List?> getFileData() {
    return MatrixMxcImage.retryUntilOnline<Uint8List?>(
      client,
      () => _MatrixStoryMediaLoader.loadBytes(client, parsed),
    );
  }

  @override
  Future<Uri?> resolve() async {
    final cached = await fileCache?.getFile(fileIdentifier);
    if (cached != null) {
      return cached;
    }

    final bytes = await getFileData();
    if (bytes == null) {
      return null;
    }

    return fileCache?.putFile(fileIdentifier, bytes);
  }

  @override
  Future<void> save(String filepath) async {
    final bytes = await getFileData();
    if (bytes == null) {
      return;
    }

    await writeLocalFileBytes(filepath, bytes);
  }
}

class _MatrixStoryImageProvider extends LODImageProvider {
  _MatrixStoryImageProvider({
    required matrix.Client client,
    required ParsedStoryEvent parsed,
    bool thumbnail = false,
  }) : super(
          id: _MatrixStoryMediaLoader.cacheIdentifier(
            parsed,
            thumbnail: thumbnail,
          ),
          loadThumbnail: null,
          loadFullRes: () => MatrixMxcImage.retryUntilOnline<Uint8List?>(
            client,
            () => _MatrixStoryMediaLoader.loadBytes(
              client,
              parsed,
              thumbnail: thumbnail,
            ),
          ),
          autoLoadFullRes: true,
        );
}

class _MatrixStoryMediaLoader {
  static String cacheIdentifier(
    ParsedStoryEvent parsed, {
    bool thumbnail = false,
  }) {
    final file = _encryptedFile(parsed, thumbnail: thumbnail);
    final hashes = _asStoryMap(file?['hashes']);
    final sha256 = hashes?['sha256'];
    final uri = thumbnail ? parsed.thumbnailUri : parsed.mediaUri;
    final kind = thumbnail ? 'thumbnail' : parsed.mediaType.jsonValue;
    return 'matrix-story-$kind-$uri-${parsed.storyId}-${sha256 ?? 'plain'}';
  }

  static Future<Uint8List?> loadBytes(
    matrix.Client client,
    ParsedStoryEvent parsed, {
    bool thumbnail = false,
  }) async {
    final uri = thumbnail ? parsed.thumbnailUri : parsed.mediaUri;
    if (uri == null) {
      return null;
    }

    final identifier = cacheIdentifier(parsed, thumbnail: thumbnail);
    if (await fileCache?.hasFile(identifier) == true) {
      final cacheUri = await fileCache?.getFile(identifier);
      if (cacheUri != null) {
        return readBytesFromUri(cacheUri);
      }
    }

    final response = await client.getContentFromUri(uri);
    var bytes = response.data;

    final encryptedFile = _encryptedFile(parsed, thumbnail: thumbnail);
    if (encryptedFile != null) {
      bytes = await _decryptStoryMediaBytes(client, encryptedFile, bytes);
    }

    await fileCache?.putFile(identifier, bytes);
    return bytes;
  }

  static Future<Uint8List> _decryptStoryMediaBytes(
    matrix.Client client,
    Map<String, Object?> file,
    Uint8List encryptedBytes,
  ) async {
    final key = _asStoryMap(file['key']);
    final hashes = _asStoryMap(file['hashes']);
    final iv = file['iv'];
    final k = key?['k'];
    final sha256 = hashes?['sha256'];
    final keyOps = key?['key_ops'];

    if (iv is! String ||
        k is! String ||
        sha256 is! String ||
        keyOps is! List ||
        !keyOps.contains('decrypt')) {
      throw StateError('Story encrypted file metadata is incomplete');
    }

    final decrypted = await client.nativeImplementations.decryptFile(
      matrix.EncryptedFile(data: encryptedBytes, iv: iv, k: k, sha256: sha256),
    );
    if (decrypted == null) {
      throw StateError('Unable to decrypt story media');
    }
    return decrypted;
  }

  static Map<String, Object?>? _encryptedFile(
    ParsedStoryEvent parsed, {
    bool thumbnail = false,
  }) {
    if (thumbnail) {
      final info = _asStoryMap(parsed.content['info']);
      return _asStoryMap(info?['thumbnail_file']);
    }

    return _asStoryMap(parsed.content['file']);
  }

  static Map<String, Object?>? _asStoryMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String) {
        result[key] = entry.value;
      }
    }
    return result;
  }
}

class MatrixStoryRoomComponent extends RoomComponent<MatrixClient, MatrixRoom>
    implements MatrixRoomSyncListener {
  MatrixStoryRoomComponent(super.client, super.room);

  Future<void> _syncQueue = Future<void>.value();

  @override
  onSync(matrix.JoinedRoomUpdate update) {
    final events = update.timeline?.events;
    if (events == null || events.isEmpty) {
      return;
    }

    final eventSnapshot = List<matrix.MatrixEvent>.of(events);
    _syncQueue = _syncQueue.then((_) {
      return _handleSyncEvents(eventSnapshot);
    }).catchError((Object error, StackTrace stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to handle serialized DM story sync events',
      );
    });
    unawaited(_syncQueue);
  }

  Future<void> _handleSyncEvents(List<matrix.MatrixEvent> events) async {
    final component = client.getComponent<MatrixStoryComponent>();
    if (component == null) {
      return;
    }

    for (final event in events) {
      try {
        await component.handleSyncEvent(room, event);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to handle DM story sync event',
        );
      }
    }
  }
}

class _StorySendResult {
  const _StorySendResult({required this.content, required this.eventId});

  final Map<String, Object?> content;
  final String? eventId;
}

class _StoryOutboxRecord {
  const _StoryOutboxRecord({
    required this.storyId,
    required this.createdAt,
    required this.expiresAt,
    required this.recipients,
    required this.media,
  });

  final String storyId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<_StoryRecipient> recipients;
  final Map<String, Object?> media;

  Map<String, Object?> toJson() => {
        'story_id': storyId,
        'created_at': createdAt.millisecondsSinceEpoch,
        'expires_at': expiresAt.millisecondsSinceEpoch,
        'recipients':
            recipients.map((recipient) => recipient.toJson()).toList(),
        'media': media,
      };

  static _StoryOutboxRecord? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final storyId = raw['story_id'];
    final createdAt = raw['created_at'];
    final expiresAt = raw['expires_at'];
    if (storyId is! String || createdAt is! int || expiresAt is! int) {
      return null;
    }

    final recipientsRaw = raw['recipients'];
    final recipients = recipientsRaw is List
        ? recipientsRaw
            .map(_StoryRecipient.fromJson)
            .whereType<_StoryRecipient>()
            .toList(growable: false)
        : const <_StoryRecipient>[];
    final mediaRaw = raw['media'];
    final media = mediaRaw is Map
        ? Map<String, Object?>.from(mediaRaw)
        : const <String, Object?>{};

    return _StoryOutboxRecord(
      storyId: storyId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true),
      recipients: recipients,
      media: media,
    );
  }
}

class _StoryRecipient {
  const _StoryRecipient({required this.roomId, required this.eventId});

  final String? roomId;
  final String? eventId;

  Map<String, Object?> toJson() => {'room_id': roomId, 'event_id': eventId};

  static _StoryRecipient? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    return _StoryRecipient(
      roomId: raw['room_id'] as String?,
      eventId: raw['event_id'] as String?,
    );
  }
}
