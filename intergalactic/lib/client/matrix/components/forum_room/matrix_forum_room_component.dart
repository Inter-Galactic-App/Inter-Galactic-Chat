import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:intergalactic/client/components/forum_room/forum_room_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:matrix/matrix.dart';

List<String> _safeStringList(Object? raw) {
  if (raw is! List) {
    return const <String>[];
  }

  return raw.whereType<String>().toList();
}

Object? _deepCopyContentValue(Object? value) {
  if (value is Map) {
    return _deepCopyContentMap(value);
  }

  if (value is List) {
    return value.map(_deepCopyContentValue).toList();
  }

  return value;
}

Map<String, Object?> _deepCopyContentMap(Map source) {
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    final key = entry.key;
    if (key is! String) {
      continue;
    }

    result[key] = _deepCopyContentValue(entry.value);
  }

  return result;
}

Map<String, Object?> _mergeContentMaps(Map base, Map overlay) {
  final merged = _deepCopyContentMap(base);

  for (final entry in overlay.entries) {
    final key = entry.key;
    if (key is! String) {
      continue;
    }

    final value = entry.value;
    final existing = merged[key];
    if (existing is Map && value is Map) {
      merged[key] = _mergeContentMaps(existing, value);
    } else {
      merged[key] = _deepCopyContentValue(value);
    }
  }

  return merged;
}

Uri? _tryParseMxcUri(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return Uri.tryParse(raw);
  }

  if (raw is Uri) {
    return raw;
  }

  return null;
}

bool _isForumVisualRoot(Event event, Map<String, Object?> content) {
  return event.type == EventTypes.Sticker ||
      content['chat.commet.type'] == 'chat.commet.sticker' ||
      content['msgtype'] == MessageTypes.Image;
}

Uri? _extractForumPreviewUri(Event event, Map<String, Object?> content) {
  final direct = _tryParseMxcUri(content['url']);
  if (direct != null) {
    return direct;
  }

  final file = content['file'];
  if (file is Map) {
    final nested = _tryParseMxcUri(file['url']);
    if (nested != null) {
      return nested;
    }
  }

  return _tryParseMxcUri(event.attachmentMxcUrl);
}

bool _looksLikeGeneratedMediaBody(
  String body,
  Map<String, Object?> content,
) {
  final filename = content['filename'] as String?;
  if (filename != null && filename.isNotEmpty && body == filename) {
    return true;
  }

  return RegExp(r'\.(gif|webp|png|jpe?g)$', caseSensitive: false)
      .hasMatch(body);
}

String _buildForumExcerpt(Event event, Map<String, Object?> content) {
  final body = (content['body'] as String?)?.trim() ?? '';
  if (body.isEmpty) {
    return '';
  }

  if (_isForumVisualRoot(event, content) &&
      _looksLikeGeneratedMediaBody(body, content)) {
    return '';
  }

  return body;
}

ImageProvider? _buildForumPreviewImage(
  Event event,
  MatrixRoom room,
  Map<String, Object?> content,
) {
  if (!_isForumVisualRoot(event, content)) {
    return null;
  }

  final uri = _extractForumPreviewUri(event, content);
  if (uri == null) {
    return null;
  }

  return MatrixMxcImage(
    uri,
    room.matrixRoom.client,
    matrixEvent: event,
    doThumbnail: false,
    autoLoadFullRes: true,
  );
}

class MatrixForumRoomComponent
    implements ForumRoomComponent<MatrixClient, MatrixRoom> {
  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  final _postsController = StreamController<void>.broadcast();
  final List<ForumPost> _posts = [];

  MatrixForumRoomComponent(this.client, this.room);

  // ── static detection ──────────────────────────────────────────────────────

  static bool isForumRoom(MatrixRoom room) {
    return room.matrixRoom.getState(EventTypes.RoomCreate)?.content['type'] ==
        'chat.intergalactic.app.forum';
  }

  // ── ForumRoomComponent ────────────────────────────────────────────────────

  @override
  List<String> get availableTags {
    // First check dedicated state event.
    final stateEvent =
        room.matrixRoom.getState('chat.intergalactic.app.forum.tags');
    if (stateEvent != null) {
      return _safeStringList(stateEvent.content['tags']);
    }

    // Fall back to m.room.create content.
    final create = room.matrixRoom.getState(EventTypes.RoomCreate);
    return _safeStringList(create?.content['ig.forum.tags']);
  }

  @override
  Stream<void> get onPostsChanged => _postsController.stream;

  @override
  List<ForumPost> get posts => List.unmodifiable(_posts);

  @override
  bool get canPost => room.permissions.canSendMessage;

  int get _moderatorTagEditPowerLevel {
    final redactLevel = room
        .matrixRoom.states[EventTypes.RoomPowerLevels]?['']?.content['redact'];
    return redactLevel is int ? redactLevel : 50;
  }

  bool _canApplyReplacementEvent({
    required Event editEvent,
    required Event originalEvent,
    required Map<String, Object?> currentContent,
    required Map<String, Object?> newContent,
  }) {
    if (editEvent.senderId == originalEvent.senderId) {
      return true;
    }

    // Forum moderators are allowed to retag a post, but only as a tag-only
    // edit that preserves the original title/body authored by the poster.
    if (room.matrixRoom.getPowerLevelByUserId(editEvent.senderId) <
        _moderatorTagEditPowerLevel) {
      return false;
    }

    return newContent['msgtype'] == currentContent['msgtype'] &&
        newContent['body'] == currentContent['body'] &&
        newContent['ig.forum.title'] == currentContent['ig.forum.title'];
  }

  @override
  Future<void> loadPosts() async {
    try {
      final tempPosts = <ForumPost>[];

      // Use the SDK's own timeline so we get raw Event objects with full content.
      final matrixTimeline = await room.matrixRoom.getTimeline();

      // getTimeline() only loads the most-recent event batch from the local
      // database (whatever arrived in the last /sync). Forum rooms need the
      // full event history to enumerate all posts, so paginate backward until
      // the beginning of the room is reached.
      const chunkSize = 100;
      while (matrixTimeline.canRequestHistory) {
        await matrixTimeline.requestHistory(historyCount: chunkSize);
      }

      final orderedEvents = List<Event>.from(matrixTimeline.events)
        ..sort((a, b) {
          final timeCompare = a.originServerTs.compareTo(b.originServerTs);
          if (timeCompare != 0) {
            return timeCompare;
          }

          return a.eventId.compareTo(b.eventId);
        });

      final eventsById = <String, Event>{
        for (final event in orderedEvents) event.eventId: event,
      };

      // ── Build an edit map ──────────────────────────────────────────────────
      // The matrix-dart-sdk does NOT automatically apply m.replace edits to
      // Event.content — the original event object always carries its original
      // content.  Scan the full timeline for replacement events and record the
      // newest effective content per original event so that editPostTags()
      // changes are reflected immediately without waiting for server-side
      // aggregation to land in a subsequent /sync.
      final Map<String, Map<String, Object?>> latestEdits = {};
      final Map<String, DateTime> latestEditTs = {};
      for (final event in orderedEvents) {
        if (event.type != EventTypes.Message) continue;
        final relatesTo =
            event.content.tryGetMap<String, Object?>('m.relates_to');
        if (relatesTo == null || relatesTo['rel_type'] != 'm.replace') {
          continue;
        }
        final targetId = relatesTo['event_id'] as String?;
        if (targetId == null) continue;
        final newContent =
            event.content.tryGetMap<String, Object?>('m.new_content');
        if (newContent == null) continue;
        final originalEvent = eventsById[targetId];
        if (originalEvent == null) continue;
        final currentContent =
            latestEdits[targetId] ?? _deepCopyContentMap(originalEvent.content);
        if (!_canApplyReplacementEvent(
          editEvent: event,
          originalEvent: originalEvent,
          currentContent: currentContent,
          newContent: newContent,
        )) {
          Log.w(
            'Ignoring forum replacement event ${event.eventId} for '
            '$targetId because it does not match the original author or a '
            'moderator tag-only edit.',
          );
          continue;
        }
        // Keep only the most-recent edit for each event; originServerTs breaks ties.
        final prev = latestEditTs[targetId];
        if (prev == null || event.originServerTs.isAfter(prev)) {
          latestEdits[targetId] = _mergeContentMaps(currentContent, newContent);
          latestEditTs[targetId] = event.originServerTs;
        }
      }

      // Count replies per thread root.
      final Map<String, int> replyCounts = {};
      for (final event in orderedEvents) {
        final relatesTo =
            event.content.tryGetMap<String, Object?>('m.relates_to');
        if (relatesTo == null) continue;
        if (relatesTo['rel_type'] != 'm.thread') continue;
        final rootId = relatesTo['event_id'] as String?;
        if (rootId == null) continue;
        replyCounts[rootId] = (replyCounts[rootId] ?? 0) + 1;
      }

      for (final event in orderedEvents) {
        // Forum roots can be regular messages or true sticker events.
        if (event.type != EventTypes.Message &&
            event.type != EventTypes.Sticker) {
          continue;
        }

        // Skip thread replies (rel_type == m.thread) and edit events
        // (rel_type == m.replace).  Edit events belong to posts already in the
        // list — they must not appear as separate entries.
        final relatesTo =
            event.content.tryGetMap<String, Object?>('m.relates_to');
        if (relatesTo != null) {
          final relType = relatesTo['rel_type'];
          if (relType == 'm.thread' || relType == 'm.replace') continue;
        }

        // Overlay the latest edit content if one exists.  The SDK stores the
        // original raw content in Event.content regardless of any edits, so we
        // merge manually from the edit map built above.
        final effectiveContent =
            latestEdits[event.eventId] ?? _deepCopyContentMap(event.content);

        // Must have a forum title to count as a post.
        final title = effectiveContent['ig.forum.title'] as String?;
        if (title == null || title.isEmpty) continue;

        final excerpt = _buildForumExcerpt(event, effectiveContent);
        final tags = _safeStringList(effectiveContent['ig.forum.tags']);
        final previewImage =
            _buildForumPreviewImage(event, room, effectiveContent);

        final sender = room.getMemberOrFallback(event.senderId);
        ImageProvider? avatar = sender.avatar;
        if (avatar == null) {
          final avatarUrl = event.senderFromMemoryOrFallback.avatarUrl;
          if (avatarUrl != null) {
            avatar = MatrixMxcImage(avatarUrl, room.matrixRoom.client,
                autoLoadFullRes: false);
          }
        }

        tempPosts.add(ForumPost(
          eventId: event.eventId,
          title: title,
          excerpt: excerpt,
          previewImage: previewImage,
          tags: tags,
          senderId: event.senderId,
          senderDisplayName: sender.displayName,
          senderAvatar: avatar,
          replyCount: replyCounts[event.eventId] ?? 0,
          timestamp: event.originServerTs,
          editableContent: Map<String, Object?>.from(effectiveContent),
        ));
      }

      // Sort newest first.
      tempPosts.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _posts
        ..clear()
        ..addAll(tempPosts);
      _postsController.add(null);
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: "Failed to load forum posts");
    }
  }

  @override
  Future<void> createPost({
    required String title,
    required String body,
    required List<String> tags,
  }) async {
    await room.matrixRoom.sendEvent({
      'msgtype': MessageTypes.Text,
      'body': body,
      'ig.forum.title': title,
      'ig.forum.tags': tags,
    });

    // Reload so the new post shows up immediately.
    await loadPosts();
  }

  // ── Tag editing ───────────────────────────────────────────────────────────

  @override
  bool canEditTags(ForumPost post) {
    // Post authors can always edit their own tags.
    if (post.senderId == room.matrixRoom.client.userID) return true;
    // Moderators/admins (redact power level) can edit anyone's tags.
    return room.permissions.canDeleteOtherUserMessages;
  }

  @override
  Future<void> editPostTags(ForumPost post, List<String> newTags) async {
    final updatedContent = Map<String, Object?>.from(post.editableContent)
      ..['ig.forum.tags'] = newTags;
    final editSummary = post.excerpt.isNotEmpty ? post.excerpt : post.title;

    // Send a Matrix edit event (m.replace) with the updated tag list.
    // Title/body/media payload are preserved unchanged; only ig.forum.tags changes.
    await room.matrixRoom.sendEvent({
      'msgtype': MessageTypes.Text,
      'body': '* $editSummary',
      'm.relates_to': {
        'rel_type': 'm.replace',
        'event_id': post.eventId,
      },
      'm.new_content': updatedContent,
    });

    // Refresh the post list so the card updates immediately.
    await loadPosts();
  }
}
