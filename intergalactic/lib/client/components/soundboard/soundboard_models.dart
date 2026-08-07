class SoundboardEventTypes {
  static const String soundState = 'chat.intergalactic.soundboard.sound';
  static const String userState = 'chat.intergalactic.soundboard.user';
  static const String play = 'chat.intergalactic.soundboard.play';
}

class SoundboardSound {
  const SoundboardSound({
    required this.id,
    required this.name,
    required this.emoji,
    required this.mxcUri,
    required this.mimeType,
    required this.uploadedBy,
    required this.createdAt,
    required this.sizeBytes,
    this.durationMs,
    this.volume = defaultVolume,
    this.enabled = true,
    this.deleted = false,
  });

  static const double minVolume = 0;
  static const double maxVolume = 150;
  static const double defaultVolume = 100;

  final String id;
  final String name;
  final String emoji;
  final Uri mxcUri;
  final String mimeType;
  final String uploadedBy;
  final DateTime createdAt;
  final int sizeBytes;
  final int? durationMs;
  final double volume;
  final bool enabled;
  final bool deleted;

  bool get isAvailable => enabled && !deleted;

  SoundboardSound copyWith({
    String? name,
    String? emoji,
    Uri? mxcUri,
    String? mimeType,
    String? uploadedBy,
    DateTime? createdAt,
    int? sizeBytes,
    int? durationMs,
    double? volume,
    bool? enabled,
    bool? deleted,
  }) {
    return SoundboardSound(
      id: id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      mxcUri: mxcUri ?? this.mxcUri,
      mimeType: mimeType ?? this.mimeType,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      createdAt: createdAt ?? this.createdAt,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      durationMs: durationMs ?? this.durationMs,
      volume: volume == null ? this.volume : normalizeVolume(volume),
      enabled: enabled ?? this.enabled,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toStateContent() {
    return {
      'id': id,
      'name': name,
      'emoji': emoji,
      'url': mxcUri.toString(),
      'mimetype': mimeType,
      'uploaded_by': uploadedBy,
      'created_at': createdAt.toUtc().toIso8601String(),
      'size_bytes': sizeBytes,
      if (durationMs != null) 'duration_ms': durationMs,
      // Matrix events use canonical JSON; keep this numeric field integral so
      // homeservers do not reject sound state events that otherwise pass power
      // level checks.
      'volume': normalizeVolume(volume).round(),
      'enabled': enabled,
      'deleted': deleted,
    };
  }

  static SoundboardSound? fromState(
    String id,
    Map<String, dynamic>? content,
  ) {
    if (content == null || content.isEmpty) {
      return null;
    }

    final rawUrl = content['url'];
    final rawName = content['name'];
    final rawEmoji = content['emoji'];
    final rawMime = content['mimetype'];
    final rawUploadedBy = content['uploaded_by'];
    final rawCreatedAt = content['created_at'];
    final rawSizeBytes = content['size_bytes'];
    if (rawUrl is! String ||
        rawName is! String ||
        rawEmoji is! String ||
        rawMime is! String ||
        rawUploadedBy is! String ||
        rawCreatedAt is! String ||
        rawSizeBytes is! num) {
      return null;
    }

    final uri = Uri.tryParse(rawUrl);
    final createdAt = DateTime.tryParse(rawCreatedAt);
    if (uri == null || uri.scheme != 'mxc' || createdAt == null) {
      return null;
    }

    final duration = content['duration_ms'];
    final rawVolume = content['volume'];
    return SoundboardSound(
      id: id,
      name: rawName,
      emoji: rawEmoji,
      mxcUri: uri,
      mimeType: rawMime,
      uploadedBy: rawUploadedBy,
      createdAt: createdAt,
      sizeBytes: rawSizeBytes.toInt(),
      durationMs: duration is num ? duration.toInt() : null,
      volume: rawVolume is num
          ? normalizeVolume(rawVolume.toDouble())
          : defaultVolume,
      enabled: content['enabled'] is bool ? content['enabled'] as bool : true,
      deleted: content['deleted'] is bool ? content['deleted'] as bool : false,
    );
  }

  static double normalizeVolume(double value) {
    if (!value.isFinite) {
      return defaultVolume;
    }
    return value.clamp(minVolume, maxVolume).toDouble();
  }
}

class SoundboardUserSettings {
  const SoundboardUserSettings({this.joinSoundId});

  final String? joinSoundId;

  Map<String, dynamic> toStateContent() {
    return {
      if (joinSoundId != null) 'join_sound_id': joinSoundId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static SoundboardUserSettings fromState(Map<String, dynamic>? content) {
    final joinSoundId = content?['join_sound_id'];
    return SoundboardUserSettings(
      joinSoundId:
          joinSoundId is String && joinSoundId.isNotEmpty ? joinSoundId : null,
    );
  }
}

class SoundboardPlayEvent {
  const SoundboardPlayEvent({
    required this.soundId,
    required this.spaceRoomId,
    required this.nonce,
    required this.source,
    this.callSessionId,
  });

  final String soundId;
  final String spaceRoomId;
  final String nonce;
  final String source;
  final String? callSessionId;

  Map<String, dynamic> toContent() {
    final sessionId = callSessionId;
    return {
      'sound_id': soundId,
      'space_room_id': spaceRoomId,
      'nonce': nonce,
      'source': source,
      if (sessionId != null && sessionId.isNotEmpty)
        'call_session_id': sessionId,
    };
  }

  static SoundboardPlayEvent? fromContent(Map<String, dynamic>? content) {
    if (content == null) {
      return null;
    }

    final soundId = content['sound_id'];
    final spaceRoomId = content['space_room_id'];
    final nonce = content['nonce'];
    final source = content['source'];
    if (soundId is! String ||
        soundId.isEmpty ||
        spaceRoomId is! String ||
        spaceRoomId.isEmpty ||
        nonce is! String ||
        nonce.isEmpty) {
      return null;
    }

    final callSessionId = content['call_session_id'];
    return SoundboardPlayEvent(
      soundId: soundId,
      spaceRoomId: spaceRoomId,
      nonce: nonce,
      source: source is String && source.isNotEmpty ? source : 'manual',
      callSessionId: callSessionId is String && callSessionId.isNotEmpty
          ? callSessionId
          : null,
    );
  }
}
