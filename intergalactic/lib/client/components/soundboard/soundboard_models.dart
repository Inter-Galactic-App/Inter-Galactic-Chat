import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';

class SoundboardConstraints {
  static const int maxSoundBytes = 2 * 1024 * 1024;
  static const int recommendedMaxDurationMs = 8000;
  static const Duration recommendedMaxDuration = Duration(
    milliseconds: recommendedMaxDurationMs,
  );
}

class SoundboardEventTypes {
  static const String soundState = 'chat.intergalactic.soundboard.sound';
  static const String packState = 'chat.intergalactic.soundboard.pack';

  /// Service-owned per-space config written when a space opts into enhanced
  /// protection (state key ""). Its presence marks the space as protected: the
  /// client routes soundboard mutations through the authority service instead
  /// of writing state directly (DECISIONS.md 2026-07-17, per-space opt-in).
  static const String authorityConfig =
      'chat.intergalactic.soundboard.authority';
  static const String destinationPolicyState =
      'chat.intergalactic.soundboard.destination_policy';
  static const String userState = 'chat.intergalactic.soundboard.user';
  static const String play = 'chat.intergalactic.soundboard.play';

  /// Room account data holding the member's personal active-pack overrides.
  static const String localPackSettings =
      'chat.intergalactic.soundboard.local_packs';

  /// Account-level (not room) account data listing the source packs a member
  /// has enabled globally, so their sounds are reachable from every space that
  /// allows external packs (U5). Holds references only — never copies of the
  /// sounds, which stay owned by their source space.
  static const String globalPackReferences =
      'chat.intergalactic.soundboard.global_packs';
}

/// One globally enabled pack, identified by the space that owns it plus the
/// pack id. Both halves are required: pack ids are unique only within their
/// source space, and the source is what later authorizes (or invalidates)
/// playback.
class SoundboardGlobalPackReference {
  const SoundboardGlobalPackReference({
    required this.sourceSpaceId,
    required this.packId,
    this.enabledAt,
  });

  final String sourceSpaceId;
  final String packId;
  final DateTime? enabledAt;

  /// Identity for merge and de-duplication. Two references naming the same
  /// pack in the same space are the same reference regardless of when each
  /// client enabled it.
  String get key => keyFor(sourceSpaceId, packId);

  static String keyFor(String sourceSpaceId, String packId) =>
      jsonEncode([sourceSpaceId, packId]);

  Map<String, dynamic> toContent() => {
    'source_space_id': sourceSpaceId,
    'pack_id': packId,
    if (enabledAt != null) 'enabled_at': enabledAt!.toUtc().toIso8601String(),
  };

  /// Returns null for anything that is not a usable reference. A malformed
  /// entry must not abort the whole document: another client (or a newer app
  /// version) may have written entries this build does not understand, and
  /// dropping the readable ones would destroy them on the next write.
  static SoundboardGlobalPackReference? fromContent(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final sourceSpaceId = raw['source_space_id'];
    final packId = raw['pack_id'];
    if (sourceSpaceId is! String ||
        sourceSpaceId.isEmpty ||
        packId is! String ||
        packId.isEmpty) {
      return null;
    }
    final enabledAtRaw = raw['enabled_at'];
    return SoundboardGlobalPackReference(
      sourceSpaceId: sourceSpaceId,
      packId: packId,
      enabledAt: enabledAtRaw is String
          ? DateTime.tryParse(enabledAtRaw)?.toUtc()
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SoundboardGlobalPackReference && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The member's account-global soundboard library: the set of source packs
/// they have enabled across their spaces.
///
/// This document is shared by every device on the account, so writes are
/// read-modify-write over the latest synchronized copy rather than blind
/// overwrites — see [mergeWith].
class SoundboardGlobalLibrary {
  const SoundboardGlobalLibrary({this.references = const []});

  final List<SoundboardGlobalPackReference> references;

  bool contains(String sourceSpaceId, String packId) => references.any(
    (r) => r.sourceSpaceId == sourceSpaceId && r.packId == packId,
  );

  List<SoundboardGlobalPackReference> referencesFor(String sourceSpaceId) =>
      references.where((r) => r.sourceSpaceId == sourceSpaceId).toList();

  SoundboardGlobalLibrary withReference(
    SoundboardGlobalPackReference reference,
  ) {
    final next =
        references.where((r) => r.key != reference.key).toList(growable: true)
          ..add(reference);
    return SoundboardGlobalLibrary(references: next);
  }

  SoundboardGlobalLibrary withoutReference(
    String sourceSpaceId,
    String packId,
  ) {
    final removed = SoundboardGlobalPackReference.keyFor(sourceSpaceId, packId);
    return SoundboardGlobalLibrary(
      references: references.where((r) => r.key != removed).toList(),
    );
  }

  /// Rebases this library's intended change onto [latest], the newest
  /// synchronized copy of the document.
  ///
  /// Another device may have enabled or disabled unrelated packs since this
  /// one last read. Those entries must survive: the only differences this
  /// client is entitled to impose are the ones it made itself, expressed as
  /// [added] and [removed] keys. Everything else in [latest] wins.
  SoundboardGlobalLibrary mergeWith(
    SoundboardGlobalLibrary latest, {
    Iterable<SoundboardGlobalPackReference> added = const [],
    Iterable<String> removedKeys = const [],
  }) {
    final removed = removedKeys.toSet();
    final merged = <String, SoundboardGlobalPackReference>{
      for (final reference in latest.references)
        if (!removed.contains(reference.key)) reference.key: reference,
    };
    for (final reference in added) {
      merged[reference.key] = reference;
    }
    return SoundboardGlobalLibrary(references: merged.values.toList());
  }

  Map<String, dynamic> toContent() => {
    'packs': references.map((r) => r.toContent()).toList(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  static SoundboardGlobalLibrary fromContent(Map<String, dynamic>? content) {
    final raw = content?['packs'];
    if (raw is! List) {
      return const SoundboardGlobalLibrary();
    }
    final seen = <String>{};
    final references = <SoundboardGlobalPackReference>[];
    for (final entry in raw) {
      final reference = SoundboardGlobalPackReference.fromContent(entry);
      // Duplicates are a merge artifact, not intent; keep the first.
      if (reference != null && seen.add(reference.key)) {
        references.add(reference);
      }
    }
    return SoundboardGlobalLibrary(references: references);
  }
}

/// Whether an external (out-of-space) pack may be played into a destination.
///
/// One evaluator for both ends of the wire: a sender uses it before emitting
/// and a receiver uses it again before playing, so a policy change cannot be
/// bypassed by a client that evaluated it earlier — or by a sender that never
/// evaluated it at all.
class SoundboardExternalPackEvaluation {
  const SoundboardExternalPackEvaluation._(this.allowed, this.reason);

  static const SoundboardExternalPackEvaluation _ok =
      SoundboardExternalPackEvaluation._(true, null);

  final bool allowed;
  final String? reason;

  bool get isBlocked => !allowed;

  /// [destinationSpaceId] is null when a call has no explicit Matrix
  /// destination space. That is refused rather than allowed: with no
  /// destination there is no policy to honour, and playing anyway would let a
  /// caller route around a block by picking a context that has none.
  static SoundboardExternalPackEvaluation evaluate({
    required String sourceSpaceId,
    required String? destinationSpaceId,
    required SoundboardDestinationPolicy destinationPolicy,
  }) {
    if (destinationSpaceId == null || destinationSpaceId.isEmpty) {
      return const SoundboardExternalPackEvaluation._(
        false,
        'This call has no space, so packs from other spaces cannot be played here.',
      );
    }
    // Same-space playback is not external and is never subject to this policy.
    if (sourceSpaceId == destinationSpaceId) {
      return _ok;
    }
    if (!destinationPolicy.allowExternalPacks) {
      return const SoundboardExternalPackEvaluation._(
        false,
        'This space does not allow sound packs from other spaces.',
      );
    }
    return _ok;
  }
}

/// Per-space personal pack activation overrides (room account data).
///
/// Defaults are derived, not written: a member's own packs are active and
/// other creators' packs are inactive until the member opts in (KTD3). Only
/// explicit deviations from that default are stored, so most members never
/// write this document.
class SoundboardLocalPackSettings {
  const SoundboardLocalPackSettings({this.overrides = const {}});

  final Map<String, bool> overrides;

  bool? overrideFor(String packId) => overrides[packId];

  SoundboardLocalPackSettings withOverride(String packId, bool? active) {
    final next = Map<String, bool>.from(overrides);
    if (active == null) {
      next.remove(packId);
    } else {
      next[packId] = active;
    }
    return SoundboardLocalPackSettings(overrides: next);
  }

  Map<String, dynamic> toContent() {
    return {
      'active_overrides': overrides,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static SoundboardLocalPackSettings fromContent(
    Map<String, dynamic>? content,
  ) {
    final raw = content?['active_overrides'];
    if (raw is! Map) {
      return const SoundboardLocalPackSettings();
    }
    final overrides = <String, bool>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && key.isNotEmpty && value is bool) {
        overrides[key] = value;
      }
    }
    return SoundboardLocalPackSettings(overrides: overrides);
  }
}

/// A display-only caption for a pack in one space.
///
/// A legacy pack has a stable per-uploader id, but loose sounds from several
/// uploaders used to all render as `Legacy sounds`. Persisted legacy-era packs
/// can lack the historical `legacy` Boolean, so number the exact unchanged
/// fallback captions rather than relying on that metadata. A member who renamed
/// a pack has already made it distinct, and their chosen label must stay
/// verbatim.
String soundboardPackDisplayName(
  SoundboardPack pack,
  Iterable<SoundboardPack> spacePacks,
) {
  if (pack.name != SoundboardPack.legacyDefaultName) {
    return pack.name;
  }

  final defaultLegacyPacks =
      spacePacks
          .where(
            (candidate) => candidate.name == SoundboardPack.legacyDefaultName,
          )
          .toList()
        ..sort((a, b) {
          final byCreated = a.createdAt.compareTo(b.createdAt);
          return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
        });
  if (defaultLegacyPacks.length < 2) {
    return pack.name;
  }

  final ordinal = defaultLegacyPacks.indexWhere(
    (candidate) => candidate.id == pack.id,
  );
  return ordinal < 0 ? pack.name : '${pack.name} ${ordinal + 1}';
}

class SoundboardPack {
  static const legacyDefaultName = 'Legacy sounds';

  const SoundboardPack({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.emoji,
    this.enabled = true,
    this.deleted = false,
    this.isLegacy = false,
    this.revision,
  });

  final String id;
  final String name;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Optional user-chosen pack icon, stored as an emoji shortcode/slug (the
  /// same representation as [SoundboardSound.emoji]). Null means no icon; UI
  /// falls back to a default folder glyph.
  final String? emoji;
  final bool enabled;
  final bool deleted;
  final bool isLegacy;

  /// The authority service's optimistic-concurrency revision, present only on
  /// service-written state (protected spaces); null for client-managed writes.
  /// Used as `expected_revision` when routing a mutation through the service.
  final int? revision;

  bool get isAvailable => enabled && !deleted;

  SoundboardPack copyWith({
    String? name,
    DateTime? updatedAt,
    String? emoji,
    bool clearEmoji = false,
    bool? enabled,
    bool? deleted,
    bool? isLegacy,
    int? revision,
  }) {
    return SoundboardPack(
      id: id,
      name: name ?? this.name,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      emoji: clearEmoji ? null : (emoji ?? this.emoji),
      enabled: enabled ?? this.enabled,
      deleted: deleted ?? this.deleted,
      isLegacy: isLegacy ?? this.isLegacy,
      revision: revision ?? this.revision,
    );
  }

  Map<String, dynamic> toStateContent() {
    return {
      'name': name,
      'created_by': createdBy,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      if (emoji != null && emoji!.isNotEmpty) 'emoji': emoji,
      'enabled': enabled,
      'deleted': deleted,
      'legacy': isLegacy,
    };
  }

  static SoundboardPack? fromState(String id, Map<String, dynamic>? content) {
    if (id.isEmpty || content == null || content.isEmpty) {
      return null;
    }

    final name = content['name'];
    // Accept both the app's canonical schema and the authority service's:
    // a service-written pack (protected space) records `creator_user_id`, while
    // client-managed writes use `created_by`. Parsing both keeps protected and
    // unprotected packs byte-compatible here, so a service-created pack is not
    // silently dropped (which read as "packs don't create" / "rename reverts").
    final createdBy = content['created_by'] ?? content['creator_user_id'];
    final createdAtRaw = content['created_at'];
    final updatedAtRaw = content['updated_at'];
    if (name is! String ||
        name.trim().isEmpty ||
        createdBy is! String ||
        createdBy.isEmpty ||
        createdAtRaw is! String ||
        updatedAtRaw is! String) {
      return null;
    }

    final createdAt = DateTime.tryParse(createdAtRaw);
    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (createdAt == null ||
        updatedAt == null ||
        updatedAt.isBefore(createdAt)) {
      return null;
    }

    final rawEmoji = content['emoji'];
    return SoundboardPack(
      id: id,
      name: name.trim(),
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      emoji: rawEmoji is String && rawEmoji.trim().isNotEmpty
          ? rawEmoji.trim()
          : null,
      // The app's canonical field is `enabled`; the authority service records
      // the inverse `disabled`. Prefer the explicit `enabled`, else derive it
      // from `disabled` (absent → enabled), so a service pack's enabled state
      // is honored instead of always defaulting to true.
      enabled: content['enabled'] is bool
          ? content['enabled'] as bool
          : (content['disabled'] is bool
                ? !(content['disabled'] as bool)
                : true),
      deleted: content['deleted'] is bool ? content['deleted'] as bool : false,
      isLegacy: content['legacy'] is bool ? content['legacy'] as bool : false,
      revision: content['revision'] is int ? content['revision'] as int : null,
    );
  }

  static String legacyIdForUploader(String uploaderId) {
    final digest = crypto.sha256.convert(utf8.encode(uploaderId)).toString();
    return 'legacy:${digest.substring(0, 24)}';
  }

  static SoundboardPack legacyForUploader(
    String uploaderId, {
    required DateTime createdAt,
  }) {
    return SoundboardPack(
      id: legacyIdForUploader(uploaderId),
      name: legacyDefaultName,
      createdBy: uploaderId,
      createdAt: createdAt,
      updatedAt: createdAt,
      isLegacy: true,
    );
  }
}

class SoundboardDestinationPolicy {
  const SoundboardDestinationPolicy({this.allowExternalPacks = true});

  /// The policy for a space that has never configured one — allow (U6). A
  /// space that never thought about external packs must behave exactly as it
  /// did before the feature existed.
  static const SoundboardDestinationPolicy allowed =
      SoundboardDestinationPolicy();

  final bool allowExternalPacks;

  Map<String, dynamic> toStateContent() => {
    'allow_external_packs': allowExternalPacks,
  };

  /// [fromState] distinguishes "absent" from "unreadable" by returning null for
  /// the latter. Enforcement wants a policy either way, and the rule is
  /// absence-means-allow, so an unreadable policy — a wrong-typed field, or a
  /// future schema this build does not understand — resolves to allow rather
  /// than silently blocking a space nobody configured.
  static SoundboardDestinationPolicy resolve(Map<String, dynamic>? content) =>
      fromState(content) ?? allowed;

  static SoundboardDestinationPolicy? fromState(Map<String, dynamic>? content) {
    if (content == null) {
      return const SoundboardDestinationPolicy();
    }
    final allowExternalPacks = content['allow_external_packs'];
    if (allowExternalPacks is! bool) {
      return null;
    }
    return SoundboardDestinationPolicy(allowExternalPacks: allowExternalPacks);
  }
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
    this.packId,
    this.revision,
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
  final String? packId;

  /// Authority-service revision; present only on service-written state
  /// (protected spaces), null for client-managed writes. Used as
  /// `expected_revision` when routing sound mutations through the service.
  final int? revision;

  bool get isAvailable => enabled && !deleted;
  bool get hasExplicitPackReference => packId != null;
  String? get legacyPackId => hasExplicitPackReference
      ? null
      : SoundboardPack.legacyIdForUploader(uploadedBy);

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
    String? packId,
    bool clearPackId = false,
    int? revision,
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
      // A sound with no reference belongs to its uploader's derived legacy
      // pack, so clearing the reference is the canonical "move to legacy".
      packId: clearPackId ? null : (packId ?? this.packId),
      revision: revision ?? this.revision,
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
      if (packId != null) 'pack_id': packId,
    };
  }

  static SoundboardSound? fromState(String id, Map<String, dynamic>? content) {
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
    final rawPackId = content['pack_id'];
    if (rawPackId != null && (rawPackId is! String || rawPackId.isEmpty)) {
      return null;
    }
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
      packId: rawPackId as String?,
      revision: content['revision'] is int ? content['revision'] as int : null,
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
      joinSoundId: joinSoundId is String && joinSoundId.isNotEmpty
          ? joinSoundId
          : null,
    );
  }
}

class SoundboardPlaySnapshot {
  const SoundboardPlaySnapshot({
    required this.mxcUri,
    required this.mimeType,
    required this.sizeBytes,
    required this.volume,
    this.durationMs,
  });

  static const int maxSizeBytes = SoundboardConstraints.maxSoundBytes;
  static const int maxDurationMs =
      SoundboardConstraints.recommendedMaxDurationMs;
  static const Set<String> allowedMimeTypes = {
    'audio/aac',
    'audio/flac',
    'audio/mp4',
    'audio/mpeg',
    'audio/ogg',
    'audio/wav',
    'audio/webm',
    'audio/x-wav',
  };

  final Uri mxcUri;
  final String mimeType;
  final int sizeBytes;

  /// Optional — see [SoundboardAuthorityMediaDescriptor.durationMs]. Nothing on
  /// the playback path reads it; it is carried so a receiver sees the same
  /// bounds the issuer signed.
  final int? durationMs;
  final double volume;

  Map<String, dynamic> toContent() {
    return {
      'url': mxcUri.toString(),
      'mimetype': mimeType,
      'size_bytes': sizeBytes,
      if (durationMs != null) 'duration_ms': durationMs,
      'volume': SoundboardSound.normalizeVolume(volume).round(),
    };
  }

  /// Builds a playable sound from the snapshot alone.
  ///
  /// Cross-space playback never resolves source-space state — the receiver may
  /// have no access to it — so the bounded snapshot IS the sound. Fields the
  /// snapshot does not carry are cosmetic (name, emoji) and are left neutral
  /// rather than invented.
  SoundboardSound asSound({required String id, required String uploadedBy}) {
    return SoundboardSound(
      id: id,
      name: id,
      emoji: '🔊',
      mxcUri: mxcUri,
      mimeType: mimeType,
      uploadedBy: uploadedBy,
      createdAt: DateTime.now().toUtc(),
      sizeBytes: sizeBytes,
      durationMs: durationMs,
      volume: volume,
    );
  }

  static SoundboardPlaySnapshot? fromContent(Map<String, dynamic>? content) {
    if (content == null) {
      return null;
    }
    final url = content['url'];
    final mimeType = content['mimetype'];
    final sizeBytes = content['size_bytes'];
    final durationMs = content['duration_ms'];
    final volume = content['volume'];
    if (url is! String ||
        mimeType is! String ||
        !allowedMimeTypes.contains(mimeType.toLowerCase()) ||
        sizeBytes is! int ||
        sizeBytes <= 0 ||
        sizeBytes > maxSizeBytes ||
        volume is! num ||
        !volume.toDouble().isFinite ||
        volume < SoundboardSound.minVolume ||
        volume > SoundboardSound.maxVolume) {
      return null;
    }
    // Absent is fine; present-but-nonsense is not.
    if (durationMs != null &&
        (durationMs is! int || durationMs <= 0 || durationMs > maxDurationMs)) {
      return null;
    }

    final mxcUri = Uri.tryParse(url);
    if (mxcUri == null ||
        mxcUri.scheme != 'mxc' ||
        mxcUri.host.isEmpty ||
        mxcUri.pathSegments.isEmpty) {
      return null;
    }

    return SoundboardPlaySnapshot(
      mxcUri: mxcUri,
      mimeType: mimeType.toLowerCase(),
      sizeBytes: sizeBytes,
      durationMs: durationMs,
      volume: volume.toDouble(),
    );
  }
}

class SoundboardPlayEvent {
  const SoundboardPlayEvent({
    required this.soundId,
    required String spaceRoomId,
    required this.nonce,
    required this.source,
    this.callSessionId,
  }) : version = legacyVersion,
       sourceSpaceRoomId = spaceRoomId,
       destinationSpaceRoomId = null,
       packId = null,
       playedAt = null,
       snapshot = null,
       authorization = null;

  const SoundboardPlayEvent.versioned({
    required this.soundId,
    required this.packId,
    required this.sourceSpaceRoomId,
    required this.destinationSpaceRoomId,
    required this.nonce,
    required this.source,
    required this.playedAt,
    required this.snapshot,
    this.callSessionId,
    this.authorization,
  }) : version = currentVersion;

  static const int legacyVersion = 1;
  static const int currentVersion = 2;
  static const Duration maxSnapshotAge = Duration(seconds: 30);
  static const Duration maxFutureSkew = Duration(seconds: 5);
  static final RegExp _dedupeIdPattern = RegExp(r'^[A-Za-z0-9._:-]{8,128}$');

  final int version;
  final String soundId;
  final String sourceSpaceRoomId;
  final String? destinationSpaceRoomId;
  final String? packId;
  final String nonce;
  final String source;
  final String? callSessionId;
  final DateTime? playedAt;
  final SoundboardPlaySnapshot? snapshot;

  /// The service-signed authorization (U7). Present only when the sound comes
  /// from a space other than the destination: same-space playback is not
  /// external and needs no authorization, while cross-space playback is
  /// unplayable without one.
  final SoundboardPlaybackAuthorization? authorization;

  String get spaceRoomId => sourceSpaceRoomId;
  bool get isLegacy => version == legacyVersion;

  /// True when the sound is owned by a different space than the one the call
  /// belongs to. Legacy events are never cross-space: they predate the concept
  /// and always name a single space.
  bool get isCrossSpace =>
      !isLegacy &&
      destinationSpaceRoomId != null &&
      sourceSpaceRoomId != destinationSpaceRoomId;

  bool isFreshAt(DateTime now) {
    final eventTime = playedAt;
    if (isLegacy || eventTime == null) {
      return true;
    }
    final referenceTime = now.toUtc();
    return referenceTime.difference(eventTime) <= maxSnapshotAge &&
        eventTime.difference(referenceTime) <= maxFutureSkew;
  }

  Map<String, dynamic> toContent() {
    final sessionId = callSessionId;
    if (isLegacy) {
      return {
        'sound_id': soundId,
        'space_room_id': sourceSpaceRoomId,
        'nonce': nonce,
        'source': source,
        if (sessionId != null && sessionId.isNotEmpty)
          'call_session_id': sessionId,
      };
    }

    return {
      'v': version,
      'sound_id': soundId,
      'pack_id': packId,
      'source_space_room_id': sourceSpaceRoomId,
      'destination_space_room_id': destinationSpaceRoomId,
      'nonce': nonce,
      'source': source,
      'played_at': playedAt?.toUtc().toIso8601String(),
      'snapshot': snapshot?.toContent(),
      if (authorization != null) 'authorization': authorization!.toJson(),
      if (sessionId != null && sessionId.isNotEmpty)
        'call_session_id': sessionId,
    };
  }

  static SoundboardPlayEvent? fromContent(
    Map<String, dynamic>? content, {
    DateTime? now,
  }) {
    if (content == null) {
      return null;
    }

    final version = content['v'];
    if (version == null) {
      return _fromLegacyContent(content);
    }
    if (version is! int || version != currentVersion) {
      return null;
    }

    final soundId = content['sound_id'];
    final packId = content['pack_id'];
    final sourceSpaceRoomId = content['source_space_room_id'];
    final destinationSpaceRoomId = content['destination_space_room_id'];
    final nonce = content['nonce'];
    final playedAtRaw = content['played_at'];
    final snapshotRaw = content['snapshot'];
    if (soundId is! String ||
        soundId.isEmpty ||
        packId is! String ||
        packId.isEmpty ||
        sourceSpaceRoomId is! String ||
        sourceSpaceRoomId.isEmpty ||
        destinationSpaceRoomId is! String ||
        destinationSpaceRoomId.isEmpty ||
        nonce is! String ||
        !_dedupeIdPattern.hasMatch(nonce) ||
        playedAtRaw is! String ||
        snapshotRaw is! Map) {
      return null;
    }

    final playedAt = DateTime.tryParse(playedAtRaw)?.toUtc();
    Map<String, dynamic> snapshotContent;
    try {
      snapshotContent = Map<String, dynamic>.from(snapshotRaw);
    } on Object {
      return null;
    }
    final snapshot = SoundboardPlaySnapshot.fromContent(snapshotContent);
    if (playedAt == null || snapshot == null) {
      return null;
    }

    final source = content['source'];
    final callSessionId = content['call_session_id'];
    final authorizationRaw = content['authorization'];
    final authorization = authorizationRaw is Map
        ? SoundboardPlaybackAuthorization.fromJson(
            Map<String, dynamic>.from(authorizationRaw),
          )
        : null;
    // A present-but-unparseable authorization is a rejection, not a downgrade
    // to an unauthorized play: an event that claims to carry one must carry a
    // usable one.
    if (authorizationRaw != null && authorization == null) {
      return null;
    }
    final event = SoundboardPlayEvent.versioned(
      soundId: soundId,
      packId: packId,
      sourceSpaceRoomId: sourceSpaceRoomId,
      destinationSpaceRoomId: destinationSpaceRoomId,
      nonce: nonce,
      source: source is String && source.isNotEmpty ? source : 'manual',
      callSessionId: callSessionId is String && callSessionId.isNotEmpty
          ? callSessionId
          : null,
      playedAt: playedAt,
      snapshot: snapshot,
      authorization: authorization,
    );
    // Cross-space playback without an authorization is refused at parse time,
    // so no later code has to remember to check: the only way to play another
    // space's sound is to carry the service's signature for it.
    if (event.isCrossSpace && authorization == null) {
      return null;
    }
    if (!event.isFreshAt(now ?? DateTime.now())) {
      return null;
    }
    return event;
  }

  static SoundboardPlayEvent? _fromLegacyContent(Map<String, dynamic> content) {
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
