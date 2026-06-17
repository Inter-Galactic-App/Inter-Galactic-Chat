import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';

const String storyPhotoEventType = 'chat.intergalactic.story.photo';
const String storyVideoEventType = 'chat.intergalactic.story.video';
const String storyReactionEventType = 'chat.intergalactic.story.reaction';
const String storyOutboxAccountDataKey = 'chat.intergalactic.stories.outbox.v1';
const String storyViewedAccountDataKey = 'chat.intergalactic.stories.viewed.v1';
const String storyNotificationSettingsAccountDataKey =
    'chat.intergalactic.stories.notification_settings.v1';
const Duration storyLifetime = Duration(hours: 24);
const Duration storyMaxVideoDuration = Duration(seconds: 30);
const int storyMaxImageBytes = 50 * 1024 * 1024;
const int storyMaxVideoBytes = 100 * 1024 * 1024;
const int storyDefaultVideoBackgroundColor = 0xFF000000;
const List<String> storyReactionChoices = [
  '\u{2764}\u{FE0F}',
  '\u{1F602}',
  '\u{1F62E}',
  '\u{1F622}',
  '\u{1F525}',
  '\u{1F44D}',
];

bool storyImageSizeIsAllowed(
  int sizeBytes, {
  int maxImageBytes = storyMaxImageBytes,
}) =>
    sizeBytes >= 0 && sizeBytes <= maxImageBytes;

bool storyVideoSizeIsAllowed(
  int sizeBytes, {
  int maxVideoBytes = storyMaxVideoBytes,
}) =>
    sizeBytes >= 0 && sizeBytes <= maxVideoBytes;

enum StoryMediaType {
  image,
  video;

  static StoryMediaType? fromJson(Object? value) => switch (value) {
        'image' => StoryMediaType.image,
        'video' => StoryMediaType.video,
        _ => null,
      };

  String get jsonValue => switch (this) {
        StoryMediaType.image => 'image',
        StoryMediaType.video => 'video',
      };
}

enum StoryMediaOverlayType {
  text,
  emoji,
  sticker;

  static StoryMediaOverlayType? fromJson(Object? value) => switch (value) {
        'text' => StoryMediaOverlayType.text,
        'emoji' => StoryMediaOverlayType.emoji,
        'sticker' => StoryMediaOverlayType.sticker,
        _ => null,
      };

  String get jsonValue => switch (this) {
        StoryMediaOverlayType.text => 'text',
        StoryMediaOverlayType.emoji => 'emoji',
        StoryMediaOverlayType.sticker => 'sticker',
      };
}

class StoryMediaOverlay {
  const StoryMediaOverlay({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotationRadians,
    this.content,
    this.mediaUri,
    this.color,
    this.backgroundColor,
    this.fontSize,
    this.bold = false,
    this.italic = false,
  });

  final String id;
  final StoryMediaOverlayType type;
  final String? content;
  final Uri? mediaUri;
  final double x;
  final double y;
  final double scale;
  final double rotationRadians;
  final int? color;
  final int? backgroundColor;
  final double? fontSize;
  final bool bold;
  final bool italic;

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.jsonValue,
        if (content != null) 'content': content,
        if (mediaUri != null) 'media_uri': mediaUri.toString(),
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotationRadians,
        if (color != null) 'color': color,
        if (backgroundColor != null) 'background_color': backgroundColor,
        if (fontSize != null) 'font_size': fontSize,
        if (bold) 'bold': true,
        if (italic) 'italic': true,
      };

  static StoryMediaOverlay? fromJson(Object? raw) {
    final map = _asStringKeyedMap(raw);
    if (map == null) {
      return null;
    }

    final id = map['id'];
    final type = StoryMediaOverlayType.fromJson(map['type']);
    final x = _asDouble(map['x']);
    final y = _asDouble(map['y']);
    final scale = _asDouble(map['scale']);
    final rotation = _asDouble(map['rotation']);
    if (id is! String ||
        id.trim().isEmpty ||
        type == null ||
        x == null ||
        y == null ||
        scale == null ||
        rotation == null ||
        !x.isFinite ||
        !y.isFinite ||
        !scale.isFinite ||
        !rotation.isFinite ||
        x < -1 ||
        x > 2 ||
        y < -1 ||
        y > 2 ||
        scale <= 0 ||
        scale > 8) {
      return null;
    }

    final content = map['content'];
    final mediaUri = _parseMxcUri(map['media_uri']);
    final color = _asInt(map['color']);
    final backgroundColor = _asInt(map['background_color']);
    final fontSize = _asDouble(map['font_size']);
    return StoryMediaOverlay(
      id: id.trim(),
      type: type,
      content: content is String ? content : null,
      mediaUri: mediaUri,
      x: x,
      y: y,
      scale: scale,
      rotationRadians: rotation,
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      bold: map['bold'] == true,
      italic: map['italic'] == true,
    );
  }
}

class StoryPhotoUpload {
  const StoryPhotoUpload({
    required this.bytes,
    required this.name,
    this.mimeType,
    this.mentionedUserIds = const [],
  });

  final Uint8List bytes;
  final String name;
  final String? mimeType;
  final List<String> mentionedUserIds;

  StoryPhotoUpload copyWith({
    Uint8List? bytes,
    String? name,
    String? mimeType,
    List<String>? mentionedUserIds,
  }) {
    return StoryPhotoUpload(
      bytes: bytes ?? this.bytes,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      mentionedUserIds: mentionedUserIds ?? this.mentionedUserIds,
    );
  }
}

class StoryVideoUpload {
  const StoryVideoUpload({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.duration,
    required this.width,
    required this.height,
    this.thumbnailBytes,
    this.thumbnailMimeType,
    this.trimStart = Duration.zero,
    this.trimEnd,
    this.overlays = const [],
    this.mentionedUserIds = const [],
    this.backgroundColor = storyDefaultVideoBackgroundColor,
  });

  final String path;
  final String name;
  final String? mimeType;
  final int sizeBytes;
  final Duration duration;
  final int? width;
  final int? height;
  final Uint8List? thumbnailBytes;
  final String? thumbnailMimeType;
  final Duration trimStart;
  final Duration? trimEnd;
  final List<StoryMediaOverlay> overlays;
  final List<String> mentionedUserIds;
  final int backgroundColor;

  Duration get effectiveTrimEnd => trimEnd ?? duration;

  Duration get selectedDuration => effectiveTrimEnd - trimStart;

  bool get usesFullSource =>
      trimStart == Duration.zero && effectiveTrimEnd == duration;

  bool get hasValidSelection =>
      !trimStart.isNegative &&
      effectiveTrimEnd > trimStart &&
      effectiveTrimEnd <= duration &&
      selectedDuration <= storyMaxVideoDuration;
}

class ParsedStoryEvent {
  const ParsedStoryEvent({
    required this.storyId,
    required this.createdAt,
    required this.expiresAt,
    required this.mediaUri,
    this.mediaType = StoryMediaType.image,
    required this.encrypted,
    required this.mimeType,
    required this.size,
    this.durationMs,
    this.width,
    this.height,
    this.thumbnailUri,
    this.trimStartMs,
    this.trimEndMs,
    this.overlays = const [],
    required this.mentionedUserIds,
    this.backgroundColor,
    required this.content,
  });

  final String storyId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Uri mediaUri;
  final StoryMediaType mediaType;
  final bool encrypted;
  final String? mimeType;
  final int? size;
  final int? durationMs;
  final int? width;
  final int? height;
  final Uri? thumbnailUri;
  final int? trimStartMs;
  final int? trimEndMs;
  final List<StoryMediaOverlay> overlays;
  final List<String> mentionedUserIds;
  final int? backgroundColor;
  final Map<String, Object?> content;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);
}

class ParsedStoryReactionEvent {
  const ParsedStoryReactionEvent({
    required this.storyId,
    required this.storyEventId,
    required this.storySenderId,
    required this.createdAt,
    required this.reaction,
    required this.mentionedUserIds,
    required this.content,
  });

  final String storyId;
  final String storyEventId;
  final String storySenderId;
  final DateTime createdAt;
  final String reaction;
  final List<String> mentionedUserIds;
  final Map<String, Object?> content;
}

class StoryItem {
  const StoryItem({
    required this.client,
    required this.storyId,
    required this.senderId,
    required this.createdAt,
    required this.expiresAt,
    required this.mediaUri,
    this.mediaType = StoryMediaType.image,
    required this.encrypted,
    required this.isOwn,
    required this.rawContent,
    this.mimeType,
    this.size,
    this.durationMs,
    this.width,
    this.height,
    this.thumbnailUri,
    this.trimStartMs,
    this.trimEndMs,
    this.overlays = const [],
    this.mentionedUserIds = const [],
    this.backgroundColor,
    this.roomId,
    this.eventId,
    this.image,
    this.thumbnail,
    this.video,
  });

  final Client client;
  final String storyId;
  final String senderId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Uri mediaUri;
  final StoryMediaType mediaType;
  final bool encrypted;
  final bool isOwn;
  final String? mimeType;
  final int? size;
  final int? durationMs;
  final int? width;
  final int? height;
  final Uri? thumbnailUri;
  final int? trimStartMs;
  final int? trimEndMs;
  final List<StoryMediaOverlay> overlays;
  final List<String> mentionedUserIds;
  final int? backgroundColor;
  final String? roomId;
  final String? eventId;
  final ImageProvider? image;
  final ImageProvider? thumbnail;
  final FileProvider? video;
  final Map<String, Object?> rawContent;

  String get seenKey => '$senderId|$storyId';

  bool get isVideo => mediaType == StoryMediaType.video;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);
}

class StoryReaction {
  const StoryReaction({
    required this.roomId,
    required this.eventId,
    required this.storyId,
    required this.storyEventId,
    required this.storySenderId,
    required this.reactorId,
    required this.reaction,
    required this.createdAt,
    this.mentionedUserIds = const [],
  });

  final String roomId;
  final String eventId;
  final String storyId;
  final String storyEventId;
  final String storySenderId;
  final String reactorId;
  final String reaction;
  final DateTime createdAt;
  final List<String> mentionedUserIds;

  String get storyKey => '$storySenderId|$storyId';
}

class StoryUploadResult {
  const StoryUploadResult({
    required this.storyCount,
    required this.sentEventCount,
    required this.targetRoomCount,
    required this.failedEventCount,
  });

  final int storyCount;
  final int sentEventCount;
  final int targetRoomCount;
  final int failedEventCount;

  bool get sentAny => sentEventCount > 0;

  bool get sentAll => sentAny && failedEventCount == 0;

  int nextRetryIndexAfter(int currentIndex) =>
      sentAll ? currentIndex + 1 : currentIndex;
}

class StoryNotificationMarker {
  const StoryNotificationMarker({
    required this.roomId,
    required this.eventId,
    required this.originServerTs,
    required this.expiresAt,
  });

  final String roomId;
  final String eventId;
  final DateTime originServerTs;
  final DateTime expiresAt;
}

enum StoryNotificationMode {
  off,
  mentionsOnly,
  contacts,
  all;

  static StoryNotificationMode fromJson(
    Object? value, {
    StoryNotificationMode fallback = StoryNotificationMode.off,
  }) {
    if (value == null) {
      return fallback;
    }
    return switch (value) {
      'mentions_only' => StoryNotificationMode.mentionsOnly,
      'contacts' => StoryNotificationMode.contacts,
      'all' => StoryNotificationMode.all,
      'off' => StoryNotificationMode.off,
      _ => fallback,
    };
  }

  String get jsonValue => switch (this) {
        StoryNotificationMode.off => 'off',
        StoryNotificationMode.mentionsOnly => 'mentions_only',
        StoryNotificationMode.contacts => 'contacts',
        StoryNotificationMode.all => 'all',
      };

  bool get enabledForDmScopedStories =>
      this == StoryNotificationMode.contacts ||
      this == StoryNotificationMode.all;

  bool shouldNotify({required bool isMention}) => switch (this) {
        StoryNotificationMode.off => false,
        StoryNotificationMode.mentionsOnly => isMention,
        StoryNotificationMode.contacts => true,
        StoryNotificationMode.all => true,
      };
}

class StoryNotificationSettings {
  const StoryNotificationSettings({
    this.storyPosts = StoryNotificationMode.off,
    this.storyReactions = StoryNotificationMode.contacts,
    this.sound = true,
  });

  final StoryNotificationMode storyPosts;
  final StoryNotificationMode storyReactions;
  final bool sound;

  StoryNotificationSettings copyWith({
    StoryNotificationMode? storyPosts,
    StoryNotificationMode? storyReactions,
    bool? sound,
  }) {
    return StoryNotificationSettings(
      storyPosts: storyPosts ?? this.storyPosts,
      storyReactions: storyReactions ?? this.storyReactions,
      sound: sound ?? this.sound,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'v': 1,
      'story_posts': storyPosts.jsonValue,
      'story_reactions': storyReactions.jsonValue,
      'sound': sound,
    };
  }
}

StoryNotificationSettings parseStoryNotificationSettingsContent(
  Map<String, Object?>? content,
) {
  if (content == null || content['v'] != 1) {
    return const StoryNotificationSettings();
  }

  final sound = content['sound'];
  return StoryNotificationSettings(
    storyPosts: StoryNotificationMode.fromJson(content['story_posts']),
    storyReactions: StoryNotificationMode.fromJson(
      content['story_reactions'],
      fallback: StoryNotificationMode.contacts,
    ),
    sound: sound is bool ? sound : true,
  );
}

int countSuppressibleStoryNotifications({
  required Iterable<StoryNotificationMarker> markers,
  required DateTime? latestOwnReceiptAt,
  required int rawNotificationCount,
  bool initialScanPending = false,
}) {
  if (rawNotificationCount <= 0) {
    return 0;
  }

  var count = 0;
  var sawMarker = false;
  for (final marker in markers) {
    sawMarker = true;
    if (latestOwnReceiptAt != null &&
        !marker.originServerTs.isAfter(latestOwnReceiptAt)) {
      continue;
    }

    count++;
  }

  if (!sawMarker && initialScanPending) {
    return rawNotificationCount;
  }

  return count.clamp(0, rawNotificationCount).toInt();
}

String storyPostNotificationDedupeKey({
  required String clientId,
  required String senderId,
  required String storyId,
}) =>
    '$clientId|$senderId|$storyId';

abstract class StoryComponent<T extends Client> extends Component<T> {
  StoryComponent(super.client);

  Stream<void> get onStoriesChanged;

  Map<String, List<StoryItem>> get activeStoriesByUser;

  List<StoryItem> activeStoriesForUser(String userId);

  bool hasActiveStories(String userId) =>
      activeStoriesForUser(userId).isNotEmpty;

  bool hasUnseenStories(String userId);

  bool hasPendingStoryUpload(String userId) => false;

  Future<R> trackPendingStoryUpload<R>(Future<R> Function() action) {
    return action();
  }

  Map<String, List<StoryReaction>> get reactionsByStory;

  List<StoryReaction> reactionsForStory(StoryItem story);

  StoryReaction? reactionForStoryByCurrentUser(StoryItem story);

  Future<void> sendStoryReaction(StoryItem story, String reaction);

  StoryNotificationSettings get notificationSettings;

  Future<void> updateNotificationSettings(StoryNotificationSettings settings);

  bool storyMentionsCurrentUser(StoryItem story) {
    final ownUserId = client.self?.identifier;
    return ownUserId != null && story.mentionedUserIds.contains(ownUserId);
  }

  bool storyReactionMentionsCurrentUser(StoryReaction reaction) {
    final ownUserId = client.self?.identifier;
    return ownUserId != null && reaction.mentionedUserIds.contains(ownUserId);
  }

  bool storyReactionTargetsKnownStory(StoryReaction reaction) {
    return activeStoriesForUser(reaction.storySenderId).any(
      (story) =>
          story.storyId == reaction.storyId &&
          story.eventId == reaction.storyEventId,
    );
  }

  bool shouldNotifyForStoryPost(StoryItem story) =>
      !story.isOwn &&
      notificationSettings.storyPosts.shouldNotify(
        isMention: storyMentionsCurrentUser(story),
      );

  bool shouldNotifyForStoryReaction(StoryReaction reaction) {
    final ownUserId = client.self?.identifier;
    return ownUserId != null &&
        reaction.storySenderId == ownUserId &&
        reaction.reactorId != ownUserId &&
        storyReactionTargetsKnownStory(reaction) &&
        notificationSettings.storyReactions.shouldNotify(
          isMention: storyReactionMentionsCurrentUser(reaction),
        );
  }

  Future<void> markStoriesSeen(String userId, Iterable<StoryItem> stories);

  Future<void> refreshStories();

  Future<StoryUploadResult> uploadPhotos(List<StoryPhotoUpload> photos);

  Future<StoryUploadResult> uploadVideos(List<StoryVideoUpload> videos);

  Future<void> deleteStory(String storyId);

  int suppressedNotificationCountForRoom({
    required String roomId,
    required DateTime? latestOwnReceiptAt,
    required int rawNotificationCount,
  }) =>
      0;
}

ParsedStoryReactionEvent? parseStoryReactionEventContent(
  Map<String, Object?>? content, {
  DateTime? now,
  Iterable<String> allowedReactions = storyReactionChoices,
}) {
  if (content == null || content['v'] != 1) {
    return null;
  }

  final storyId = content['story_id'];
  final storyEventId = content['story_event_id'];
  final storySender = content['story_sender'];
  final createdAtRaw = content['created_at'];
  final reaction = content['reaction'];
  if (storyId is! String ||
      storyId.trim().isEmpty ||
      storyEventId is! String ||
      !_looksLikeEventId(storyEventId) ||
      storySender is! String ||
      !_looksLikeUserId(storySender) ||
      createdAtRaw is! int ||
      reaction is! String ||
      reaction.trim().isEmpty ||
      reaction.length > 16 ||
      !allowedReactions.contains(reaction)) {
    return null;
  }

  final checkedAt = now ?? DateTime.now().toUtc();
  final createdAt = DateTime.fromMillisecondsSinceEpoch(
    createdAtRaw,
    isUtc: true,
  );
  if (createdAt.isAfter(checkedAt.add(const Duration(minutes: 5))) ||
      createdAt.isBefore(checkedAt.subtract(const Duration(days: 30)))) {
    return null;
  }

  final relatesTo = _asStringKeyedMap(content['m.relates_to']);
  if (relatesTo?['rel_type'] != 'm.annotation' ||
      relatesTo?['event_id'] != storyEventId ||
      relatesTo?['key'] != reaction) {
    return null;
  }

  return ParsedStoryReactionEvent(
    storyId: storyId.trim(),
    storyEventId: storyEventId,
    storySenderId: storySender,
    createdAt: createdAt,
    reaction: reaction,
    mentionedUserIds: parseStoryMentionUserIds(content),
    content: Map<String, Object?>.from(content),
  );
}

ParsedStoryEvent? parseStoryEventContent(
  Map<String, Object?>? content, {
  DateTime? now,
  int maxImageBytes = storyMaxImageBytes,
  bool allowExpired = false,
}) {
  if (content == null || content['v'] != 1) {
    return null;
  }

  final storyId = content['story_id'];
  final createdAtRaw = content['created_at'];
  final expiresAtRaw = content['expires_at'];
  if (storyId is! String ||
      storyId.trim().isEmpty ||
      createdAtRaw is! int ||
      expiresAtRaw is! int) {
    return null;
  }

  final checkedAt = now ?? DateTime.now().toUtc();
  final createdAt = DateTime.fromMillisecondsSinceEpoch(
    createdAtRaw,
    isUtc: true,
  );
  final expiresAt = DateTime.fromMillisecondsSinceEpoch(
    expiresAtRaw,
    isUtc: true,
  );
  if ((!allowExpired && !expiresAt.isAfter(checkedAt)) ||
      !expiresAt.isAfter(createdAt) ||
      createdAt.isAfter(checkedAt.add(const Duration(minutes: 5))) ||
      expiresAt.difference(createdAt) > const Duration(hours: 25)) {
    return null;
  }

  final msgType = content['msgtype'];
  if (msgType != null && msgType != 'm.image') {
    return null;
  }

  final info = _asStringKeyedMap(content['info']);
  final size = _asInt(info?['size']);
  if (size != null &&
      !storyImageSizeIsAllowed(size, maxImageBytes: maxImageBytes)) {
    return null;
  }

  final file = _asStringKeyedMap(content['file']);
  final url = content['url'];
  final encrypted = file != null;
  final uriRaw = encrypted ? file['url'] : url;
  if (uriRaw is! String || uriRaw.trim().isEmpty) {
    return null;
  }

  final mediaUri = _parseMxcUri(uriRaw);
  if (mediaUri == null) {
    return null;
  }

  final mimeType = _firstString([
    info?['mimetype'],
    file?['mimetype'],
    content['mimetype'],
  ]);
  if (mimeType != null && !mimeType.toLowerCase().startsWith('image/')) {
    return null;
  }

  if (encrypted && !_looksLikeEncryptedFile(file)) {
    return null;
  }

  return ParsedStoryEvent(
    storyId: storyId,
    createdAt: createdAt,
    expiresAt: expiresAt,
    mediaUri: mediaUri,
    mediaType: StoryMediaType.image,
    encrypted: encrypted,
    mimeType: mimeType,
    size: size,
    width: _asInt(info?['w']),
    height: _asInt(info?['h']),
    mentionedUserIds: parseStoryMentionUserIds(content),
    content: Map<String, Object?>.from(content),
  );
}

ParsedStoryEvent? parseStoryVideoEventContent(
  Map<String, Object?>? content, {
  DateTime? now,
  int maxVideoBytes = storyMaxVideoBytes,
  bool allowExpired = false,
}) {
  if (content == null || content['v'] != 1) {
    return null;
  }

  final storyId = content['story_id'];
  final createdAtRaw = content['created_at'];
  final expiresAtRaw = content['expires_at'];
  if (storyId is! String ||
      storyId.trim().isEmpty ||
      createdAtRaw is! int ||
      expiresAtRaw is! int) {
    return null;
  }

  final checkedAt = now ?? DateTime.now().toUtc();
  final createdAt = DateTime.fromMillisecondsSinceEpoch(
    createdAtRaw,
    isUtc: true,
  );
  final expiresAt = DateTime.fromMillisecondsSinceEpoch(
    expiresAtRaw,
    isUtc: true,
  );
  if ((!allowExpired && !expiresAt.isAfter(checkedAt)) ||
      !expiresAt.isAfter(createdAt) ||
      createdAt.isAfter(checkedAt.add(const Duration(minutes: 5))) ||
      expiresAt.difference(createdAt) > const Duration(hours: 25)) {
    return null;
  }

  final msgType = content['msgtype'];
  if (msgType != null && msgType != 'm.video') {
    return null;
  }

  final info = _asStringKeyedMap(content['info']);
  final size = _asInt(info?['size']);
  if (size != null &&
      !storyVideoSizeIsAllowed(size, maxVideoBytes: maxVideoBytes)) {
    return null;
  }

  final file = _asStringKeyedMap(content['file']);
  final url = content['url'];
  final encrypted = file != null;
  final uriRaw = encrypted ? file['url'] : url;
  if (uriRaw is! String || uriRaw.trim().isEmpty) {
    return null;
  }

  final mediaUri = _parseMxcUri(uriRaw);
  if (mediaUri == null) {
    return null;
  }

  final mimeType = _firstString([
    info?['mimetype'],
    file?['mimetype'],
    content['mimetype'],
  ]);
  if (mimeType != null && !mimeType.toLowerCase().startsWith('video/')) {
    return null;
  }

  if (encrypted && !_looksLikeEncryptedFile(file)) {
    return null;
  }

  final durationMs =
      _asInt(content['duration_ms']) ?? _asInt(info?['duration']);
  if (durationMs == null ||
      durationMs <= 0 ||
      durationMs > storyMaxVideoDuration.inMilliseconds) {
    return null;
  }

  final trimStartMs = _asInt(content['trim_start_ms']) ?? 0;
  final trimEndMs = _asInt(content['trim_end_ms']) ?? durationMs;
  if (trimStartMs < 0 ||
      trimEndMs <= trimStartMs ||
      trimEndMs > durationMs ||
      trimEndMs - trimStartMs > storyMaxVideoDuration.inMilliseconds) {
    return null;
  }

  final thumbnailUri = _parseStoryThumbnailUri(info);
  final backgroundColor = _asArgbColor(content['background_color']) ??
      storyDefaultVideoBackgroundColor;
  return ParsedStoryEvent(
    storyId: storyId,
    createdAt: createdAt,
    expiresAt: expiresAt,
    mediaUri: mediaUri,
    mediaType: StoryMediaType.video,
    encrypted: encrypted,
    mimeType: mimeType,
    size: size,
    durationMs: durationMs,
    width: _asInt(info?['w']),
    height: _asInt(info?['h']),
    thumbnailUri: thumbnailUri,
    trimStartMs: trimStartMs,
    trimEndMs: trimEndMs,
    overlays: parseStoryMediaOverlays(content),
    mentionedUserIds: parseStoryMentionUserIds(content),
    backgroundColor: backgroundColor,
    content: Map<String, Object?>.from(content),
  );
}

List<StoryMediaOverlay> parseStoryMediaOverlays(
  Map<String, Object?> content,
) {
  final raw = content['overlays'];
  if (raw is! List) {
    return const [];
  }

  final overlays = raw
      .map(StoryMediaOverlay.fromJson)
      .whereType<StoryMediaOverlay>()
      .take(20)
      .toList(growable: false);
  return List<StoryMediaOverlay>.unmodifiable(overlays);
}

List<String> parseStoryMentionUserIds(Map<String, Object?> content) {
  final mentions = _asStringKeyedMap(content['m.mentions']);
  final rawUserIds = mentions?['user_ids'];
  if (rawUserIds is! List) {
    return const [];
  }
  return normalizeStoryMentionUserIds(rawUserIds);
}

List<String> normalizeStoryMentionUserIds(Iterable<Object?> userIds) {
  final normalized = <String>{};
  for (final raw in userIds) {
    if (raw is! String) {
      continue;
    }
    final userId = raw.trim();
    if (_looksLikeUserId(userId)) {
      normalized.add(userId);
    }
  }
  return List<String>.unmodifiable(normalized);
}

bool _looksLikeEventId(String value) =>
    value.startsWith(r'$') && value.length > 1 && value.length <= 255;

bool _looksLikeUserId(String value) =>
    value.startsWith('@') && value.contains(':') && value.length <= 255;

Map<String, Object?>? _asStringKeyedMap(Object? value) {
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

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

int? _asArgbColor(Object? value) {
  final color = _asInt(value);
  if (color == null || color < 0 || color > 0xFFFFFFFF) {
    return null;
  }
  return color;
}

double? _asDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

String? _firstString(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
  }
  return null;
}

Uri? _parseMxcUri(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'mxc' || uri.host.isEmpty) {
    return null;
  }
  final hasMediaId = uri.pathSegments.any((segment) => segment.isNotEmpty);
  return hasMediaId ? uri : null;
}

Uri? _parseStoryThumbnailUri(Map<String, Object?>? info) {
  final direct = _parseMxcUri(info?['thumbnail_url']);
  if (direct != null) {
    return direct;
  }
  final file = _asStringKeyedMap(info?['thumbnail_file']);
  final encrypted = _parseMxcUri(file?['url']);
  if (encrypted != null) {
    return encrypted;
  }
  return null;
}

bool _looksLikeEncryptedFile(Map<String, Object?>? file) {
  if (file == null) {
    return false;
  }

  final key = _asStringKeyedMap(file['key']);
  final hashes = _asStringKeyedMap(file['hashes']);
  return file['v'] == 'v2' &&
      file['iv'] is String &&
      key?['k'] is String &&
      hashes?['sha256'] is String;
}
