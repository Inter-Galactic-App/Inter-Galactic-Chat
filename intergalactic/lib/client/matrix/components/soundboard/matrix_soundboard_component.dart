import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_signing.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_verifier.dart';
import 'package:intergalactic/client/matrix/components/soundboard/matrix_soundboard_authority_client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:uuid/uuid.dart';

/// Carries an authority-service failure out of [_authorizeCrossSpacePlay] so
/// [MatrixSoundboardComponent.playSound] can map it to a structured refusal
/// reason by its wire [error] code, instead of brittle string matching on
/// service copy that a plain `Exception(message)` would force. What the codes
/// can and cannot distinguish is documented on `_crossSpaceRefusalReason`; the
/// message is preserved either way, so the carrier never costs the caller the
/// service's own explanation.
class _CrossSpaceAuthorityRefusal implements Exception {
  const _CrossSpaceAuthorityRefusal(this.error);

  final SoundboardAuthorityError error;

  @override
  String toString() => error.message;
}

class MatrixSoundboardComponent
    implements SoundboardComponent<MatrixClient, MatrixSpace> {
  MatrixSoundboardComponent(
    this.client,
    this.space, {
    SoundboardAuthorityClient? authorityClient,
  }) : _authority =
           authorityClient ?? MatrixSoundboardAuthorityClient(client: client) {
    _stateSubscription = client.matrixClient.onRoomState.stream
        .where(
          (event) =>
              event.roomId == space.identifier &&
              (event.state.type == SoundboardEventTypes.soundState ||
                  event.state.type == SoundboardEventTypes.packState ||
                  event.state.type == SoundboardEventTypes.userState ||
                  event.state.type == SoundboardEventTypes.authorityConfig ||
                  event.state.type ==
                      SoundboardEventTypes.destinationPolicyState ||
                  event.state.type == matrix.EventTypes.RoomPowerLevels),
        )
        .listen((_) => _emitChanged());
    _syncSubscription = client.matrixClient.onSync.stream.listen(
      _handleSyncUpdate,
    );
  }

  /// Routes pack/sound mutations through the authority service when this space
  /// has opted into enhanced protection (see [isProtected]).
  final SoundboardAuthorityClient _authority;

  static const _uuid = Uuid();
  static const _joinSoundAccountDataKey = SoundboardEventTypes.userState;
  static const _localPacksAccountDataKey =
      SoundboardEventTypes.localPackSettings;

  final StreamController<void> _onChanged = StreamController.broadcast();
  final Map<String, SoundboardUserSettings> _localJoinSoundSettings = {};
  SoundboardLocalPackSettings? _localPackSettings;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _syncSubscription;
  bool _disposed = false;

  @override
  MatrixClient client;

  @override
  MatrixSpace space;

  @override
  Stream<void> get onChanged => _onChanged.stream;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await _syncSubscription?.cancel();
    _syncSubscription = null;
    final authority = _authority;
    if (authority is MatrixSoundboardAuthorityClient) {
      authority.close();
    }
    await _onChanged.close();
  }

  /// Drops locally seeded account-data caches when a sync delivers this
  /// space's soundboard account data, so overrides changed on another device
  /// (or reconciled by the server) are re-read from the synced document
  /// instead of a stale write-through cache.
  void _handleSyncUpdate(matrix.SyncUpdate update) {
    final accountData = update.rooms?.join?[space.identifier]?.accountData;
    if (accountData == null || accountData.isEmpty) {
      return;
    }

    var changed = false;
    for (final event in accountData) {
      // Notify on any relevant account-data arrival, even when no local write
      // had seeded the cache: a first-time remote override reconciles
      // roomAccountData with nothing cached, and the UI must still rebuild to
      // read it. Clearing an already-empty cache is a safe no-op.
      if (event.type == _localPacksAccountDataKey) {
        _localPackSettings = null;
        changed = true;
      } else if (event.type == _joinSoundAccountDataKey) {
        // Same write-through cache pattern as the pack overrides; the synced
        // room account data is authoritative once it arrives.
        _localJoinSoundSettings.clear();
        changed = true;
      }
    }
    if (changed) {
      _emitChanged();
      // The synced document is authoritative once it lands. If a pack was just
      // activated and `active_packs` drops here, the server echoed back
      // something other than what was written.
      Log.i(
        'soundboard event=pack_account_data_synced '
        'space_hash=${soundboardLogHash(space.identifier)} '
        'component=${identityHashCode(this)} '
        'overrides=${_packSettings.overrides.length} '
        'active_packs=${activePackIds.length}',
      );
    }
  }

  String? get _currentUserId =>
      client.matrixClient.userID ?? client.self?.identifier;

  /// Available sounds regardless of their pack's state (management view).
  List<SoundboardSound> get _availableSounds {
    final rawStates = space.matrixRoom.states[SoundboardEventTypes.soundState];
    if (rawStates == null) {
      return const [];
    }

    return rawStates.entries
        .map(
          (entry) => SoundboardSound.fromState(entry.key, entry.value.content),
        )
        .whereType<SoundboardSound>()
        .where((sound) => sound.isAvailable)
        .sorted((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Explicit pack state, including tombstoned packs (internal lookups).
  Map<String, SoundboardPack> get _explicitPacks {
    final rawStates = space.matrixRoom.states[SoundboardEventTypes.packState];
    if (rawStates == null) {
      return const {};
    }

    final packs = <String, SoundboardPack>{};
    for (final entry in rawStates.entries) {
      final pack = SoundboardPack.fromState(entry.key, entry.value.content);
      if (pack != null) {
        packs[pack.id] = pack;
      }
    }
    return packs;
  }

  @override
  List<SoundboardPack> get packs {
    final explicit = _explicitPacks;
    final visible = explicit.values.where((pack) => !pack.deleted).toList();
    final legacy = SoundboardComponent.deriveLegacyPacks(
      _availableSounds,
      explicit.keys.toSet(),
    );
    return [
      ...visible,
      ...legacy,
    ].sorted((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  List<SoundboardSound> get sounds {
    final explicit = _explicitPacks;
    return _availableSounds
        .where((sound) {
          final packId = sound.packId;
          if (packId == null) {
            // Loose sound: the derived legacy pack is available unless the
            // uploader's materialized legacy pack was disabled or deleted.
            final materialized =
                explicit[SoundboardPack.legacyIdForUploader(sound.uploadedBy)];
            return materialized == null || materialized.isAvailable;
          }
          // Explicit reference: quarantine when the pack is missing, disabled,
          // or tombstoned (KTD2).
          final pack = explicit[packId];
          return pack != null && pack.isAvailable;
        })
        .toList(growable: false);
  }

  @override
  List<SoundboardSound> soundsInPack(String packId) {
    return _availableSounds
        .where((sound) => effectivePackIdFor(sound) == packId)
        .toList(growable: false);
  }

  @override
  String effectivePackIdFor(SoundboardSound sound) =>
      sound.packId ?? SoundboardPack.legacyIdForUploader(sound.uploadedBy);

  @override
  SoundboardPack? packById(String packId) =>
      packs.firstWhereOrNull((pack) => pack.id == packId);

  @override
  bool isPackActive(SoundboardPack pack) => activePackIds.contains(pack.id);

  @override
  List<SoundboardSound> get activeSounds {
    final active = activePackIds;
    return sounds
        .where((sound) => active.contains(effectivePackIdFor(sound)))
        .toList(growable: false);
  }

  SoundboardLocalPackSettings get _packSettings {
    final cached = _localPackSettings;
    if (cached != null) {
      return cached;
    }
    final accountData =
        space.matrixRoom.roomAccountData[_localPacksAccountDataKey]?.content;
    return SoundboardLocalPackSettings.fromContent(accountData);
  }

  @override
  Set<String> get activePackIds {
    final userId = _currentUserId;
    final settings = _packSettings;
    final result = <String>{};
    for (final pack in packs) {
      if (!pack.isAvailable) {
        continue;
      }
      final active =
          settings.overrideFor(pack.id) ?? (pack.createdBy == userId);
      if (active) {
        result.add(pack.id);
      }
    }
    return result;
  }

  @override
  bool get canUploadSound {
    // In a protected space the sound event is locked above members, so
    // canChangeStateEvent is the wrong gate: members upload through the service,
    // which authorizes against the recorded member-upload threshold. Mirror that
    // threshold client-side; if it is unrecorded, allow the attempt and let the
    // service be the authority.
    if (isProtected) {
      final level = _authorityMemberUploadLevel;
      if (level == null) {
        return true;
      }
      return (currentUserPowerLevel ?? defaultUserPowerLevel) >= level;
    }
    return space.matrixRoom.canChangeStateEvent(
      SoundboardEventTypes.soundState,
    );
  }

  @override
  bool get canCreatePack {
    // Pack creation shares the sound-upload threshold (contract).
    if (isProtected) {
      return canUploadSound;
    }
    return space.matrixRoom.canChangeStateEvent(SoundboardEventTypes.packState);
  }

  /// The recorded member-upload power level from the service config event
  /// (protected spaces only); null when unprotected or unrecorded.
  int? get _authorityMemberUploadLevel {
    final content = space.matrixRoom
        .getState(SoundboardEventTypes.authorityConfig, '')
        ?.content;
    final level = content?['member_upload_level'];
    return level is int ? level : null;
  }

  @override
  SoundboardDestinationPolicy get destinationPolicy =>
      SoundboardDestinationPolicy.resolve(
        space.matrixRoom
            .getState(SoundboardEventTypes.destinationPolicyState, '')
            ?.content,
      );

  @override
  bool get canManageDestinationPolicy => space.matrixRoom.canChangeStateEvent(
    SoundboardEventTypes.destinationPolicyState,
  );

  /// Whether [room] is this component's own space room, or one of its
  /// children.
  ///
  /// Checked directly against [space] instead of by scanning [client.spaces],
  /// because a room can have more than one parent: the first space that
  /// happens to claim it is not necessarily the one that owns this sound.
  bool _ownsRoom(MatrixRoom room) =>
      space.identifier == room.identifier ||
      space.roomsWithChildren.any(
        (child) => child.identifier == room.identifier,
      );

  /// The space that owns [room], scoped to this component's own client.
  String? _destinationSpaceIdFor(MatrixRoom room) {
    for (final candidate in client.spaces) {
      if (candidate.identifier == room.identifier ||
          candidate.roomsWithChildren.any(
            (child) => child.identifier == room.identifier,
          )) {
        return candidate.identifier;
      }
    }
    return null;
  }

  /// Obtains a service-signed authorization for playing this space's sound into
  /// another space's call, and builds the v2 event carrying it.
  ///
  /// Returns null when the play must not proceed. There is deliberately NO
  /// fallback to an unauthorized or legacy event: degrading on failure is
  /// exactly how a destination policy or a revoked source would get bypassed.
  Future<SoundboardPlayEvent?> _authorizeCrossSpacePlay(
    SoundboardSound sound,
    MatrixRoom room, {
    required String destinationSpaceId,
    required String? callSessionId,
    required String nonce,
    required String source,
  }) async {
    // The service binds an authorization to a call session, so a play outside
    // one cannot be authorized at all.
    if (callSessionId == null || callSessionId.isEmpty) {
      Log.w(
        'Refusing cross-space soundboard play ${sound.id}: no call session',
      );
      return null;
    }

    // Evaluate the destination's policy before asking the service. A blocked
    // destination is the sender's business too - the receiver re-checks, but
    // emitting into a space that has said no is pointless traffic.
    final destinationSpace = client.spaces.firstWhereOrNull(
      (candidate) => candidate.identifier == destinationSpaceId,
    );
    final destinationPolicy =
        destinationSpace
            ?.getComponent<SoundboardComponent>()
            ?.destinationPolicy ??
        SoundboardDestinationPolicy.allowed;
    final evaluation = SoundboardExternalPackEvaluation.evaluate(
      sourceSpaceId: space.identifier,
      destinationSpaceId: destinationSpaceId,
      destinationPolicy: destinationPolicy,
    );
    if (evaluation.isBlocked) {
      throw Exception(evaluation.reason);
    }

    final packId = effectivePackIdFor(sound);
    final result = await _authority.createPlaybackAuthorization(
      requestId: nonce,
      auth: await _authorityProof(),
      sourceSpaceId: space.identifier,
      destinationRoomId: room.identifier,
      callSessionId: callSessionId,
      packId: packId,
      soundId: sound.id,
    );
    if (result case SoundboardAuthorityFailure(error: final error)) {
      // Typed so playSound can branch on the wire code: a source space the
      // service is not in fails here, and the member needs to be told that
      // specifically rather than shown a bare "unavailable".
      throw _CrossSpaceAuthorityRefusal(error);
    }
    final authorization =
        (result as SoundboardAuthoritySuccess).value
            as SoundboardPlaybackAuthorization;

    return SoundboardPlayEvent.versioned(
      soundId: sound.id,
      packId: packId,
      sourceSpaceRoomId: space.identifier,
      destinationSpaceRoomId: destinationSpaceId,
      nonce: nonce,
      source: source,
      callSessionId: callSessionId,
      playedAt: DateTime.now().toUtc(),
      // The snapshot mirrors the authorized media, so a receiver never has to
      // consult source-space state it may not be able to read.
      snapshot: SoundboardPlaySnapshot(
        mxcUri: authorization.media.mxcUri,
        mimeType: authorization.media.mimeType,
        sizeBytes: authorization.media.sizeBytes,
        durationMs: authorization.media.durationMs,
        volume: sound.volume,
      ),
      authorization: authorization,
    );
  }

  /// Published verification keys, cached so a burst of plays in one call does
  /// not refetch per event. Short-lived by design: the contract keeps the
  /// /keys HTTP cache TTL shorter than the rotation overlap window precisely so
  /// a rotated-in kid becomes fetchable before signatures referencing it
  /// arrive, and caching longer here would defeat that.
  static const Duration _verificationKeyCacheTtl = Duration(minutes: 5);
  List<SoundboardVerificationKey>? _cachedKeys;
  DateTime? _cachedKeysAt;

  /// The fetch currently in flight, so a burst of plays arriving before the
  /// first one lands shares it instead of each issuing its own request. The
  /// TTL cache alone only dedupes the SEQUENTIAL case - every concurrent
  /// caller sees the same empty cache and starts a fetch.
  Future<SoundboardAuthorityResult<List<SoundboardVerificationKey>>>?
  _pendingKeyFetch;

  Future<List<SoundboardVerificationKey>> _verificationKeys() async {
    final cached = _cachedKeys;
    final cachedAt = _cachedKeysAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().toUtc().difference(cachedAt) <
            _verificationKeyCacheTtl) {
      return cached;
    }
    final pending = _pendingKeyFetch ??= _authority.fetchVerificationKeys();
    final SoundboardAuthorityResult<List<SoundboardVerificationKey>> result;
    try {
      result = await pending;
    } finally {
      // Only the caller that started this fetch clears it; a later one that
      // already replaced the field must not wipe its successor.
      if (identical(_pendingKeyFetch, pending)) {
        _pendingKeyFetch = null;
      }
    }
    if (result case SoundboardAuthoritySuccess(value: final keys)) {
      _cachedKeys = keys;
      _cachedKeysAt = DateTime.now().toUtc();
      return keys;
    }
    // A failed fetch does NOT fall back to a stale set indefinitely; if there
    // is nothing cached the caller gets none and fails closed.
    return cached ?? const [];
  }

  @override
  Future<SoundboardAuthorizationVerdict> verifyCrossSpacePlayback(
    SoundboardPlaybackAuthorization authorization, {
    required String destinationRoomId,
    required String? callSessionId,
    required String senderId,
    required String soundId,
    required String packId,
    DateTime? now,
  }) async {
    final verifier = SoundboardPlaybackVerifier();
    // Cheap, deterministic rejections first — a replayed or policy-blocked
    // authorization must not cost a key fetch.
    final context = verifier.checkContext(
      authorization,
      destinationRoomId: destinationRoomId,
      // This component belongs to the destination space, so its own identifier
      // is the authoritative destination space id - nothing from the event.
      destinationSpaceId: space.identifier,
      callSessionId: callSessionId,
      senderId: senderId,
      soundId: soundId,
      packId: packId,
      destinationPolicy: destinationPolicy,
      now: now ?? DateTime.now().toUtc(),
    );
    if (!context.isAllowed) {
      return context;
    }
    return verifier.verifySignature(
      authorization,
      keys: await _verificationKeys(),
    );
  }

  @override
  Future<void> setAllowExternalPacks(bool allow) async {
    if (!canManageDestinationPolicy) {
      throw Exception(
        'Only a space administrator can change the external pack policy.',
      );
    }
    // Written even when allowing, so re-allowing is an explicit, auditable
    // state change rather than a silent deletion (Matrix state cannot be
    // deleted anyway — the same soft-disable shape protection uses).
    await client.matrixClient.setRoomStateWithKey(
      space.identifier,
      SoundboardEventTypes.destinationPolicyState,
      '',
      SoundboardDestinationPolicy(allowExternalPacks: allow).toStateContent(),
    );
    await space.matrixRoom.waitForRoomInSync();
    _emitChanged();
  }

  @override
  bool get memberUploadsEnabled =>
      soundUploadPowerLevel <= defaultUserPowerLevel;

  @override
  bool get canEnableMemberUploads =>
      space.matrixRoom.canChangeStateEvent(matrix.EventTypes.RoomPowerLevels);

  @override
  int get soundUploadPowerLevel =>
      _stateEventPowerLevel(SoundboardEventTypes.soundState);

  @override
  int get packCreationPowerLevel =>
      _stateEventPowerLevel(SoundboardEventTypes.packState);

  @override
  int get defaultUserPowerLevel =>
      _powerLevelInt(_powerLevelContent['users_default'], fallback: 0);

  @override
  int? get currentUserPowerLevel {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return null;
    }
    final users = _powerLevelMap('users');
    return _powerLevelInt(
      users[currentUserId],
      fallback: defaultUserPowerLevel,
    );
  }

  @override
  bool canManageSound(SoundboardSound sound, String userId) {
    return sound.uploadedBy == userId || canEnableMemberUploads;
  }

  @override
  bool canManagePack(SoundboardPack pack, String userId) {
    return pack.createdBy == userId || canEnableMemberUploads;
  }

  @override
  Future<void> refreshSounds() async {
    await space.matrixRoom.postLoad();
    _emitChanged();
    space.notifyUpdate();
  }

  @override
  String? getJoinSoundId(String userId) {
    final currentUserId = _currentUserId;
    if (userId == currentUserId) {
      if (_localJoinSoundSettings.containsKey(userId)) {
        return _localJoinSoundSettings[userId]?.joinSoundId;
      }

      final accountData =
          space.matrixRoom.roomAccountData[_joinSoundAccountDataKey]?.content;
      if (accountData != null) {
        return SoundboardUserSettings.fromState(accountData).joinSoundId;
      }
    }

    final state = space.matrixRoom.getState(
      SoundboardEventTypes.userState,
      userId,
    );
    return SoundboardUserSettings.fromState(state?.content).joinSoundId;
  }

  @override
  Future<void> enableMemberUploads() async {
    if (!canEnableMemberUploads) {
      throw Exception('Only server admins can enable member sound uploads.');
    }

    final powerState = space.matrixRoom.getState(
      matrix.EventTypes.RoomPowerLevels,
    );
    final content = Map<String, dynamic>.from(powerState?.content ?? {});
    final events = Map<String, dynamic>.from(
      content['events'] is Map ? content['events'] as Map : const {},
    );
    events[SoundboardEventTypes.soundState] = 0;
    // Pack creation follows the sound-upload gate (KTD8) so opening uploads
    // also opens pack creation.
    events[SoundboardEventTypes.packState] = 0;
    events.remove(SoundboardEventTypes.userState);
    content['events'] = events;

    await client.matrixClient.setRoomStateWithKey(
      space.identifier,
      matrix.EventTypes.RoomPowerLevels,
      '',
      content,
    );
    await space.matrixRoom.waitForRoomInSync();
    _emitChanged();
  }

  @override
  Future<void> alignPackCreationPermission() async {
    if (!canEnableMemberUploads) {
      throw Exception('Only server admins can change pack permissions.');
    }

    final powerState = space.matrixRoom.getState(
      matrix.EventTypes.RoomPowerLevels,
    );
    final content = Map<String, dynamic>.from(powerState?.content ?? {});
    final events = Map<String, dynamic>.from(
      content['events'] is Map ? content['events'] as Map : const {},
    );
    events[SoundboardEventTypes.packState] = soundUploadPowerLevel;
    content['events'] = events;

    await client.matrixClient.setRoomStateWithKey(
      space.identifier,
      matrix.EventTypes.RoomPowerLevels,
      '',
      content,
    );
    await space.matrixRoom.waitForRoomInSync();
    _emitChanged();
  }

  @override
  Future<SoundboardPack> createPack(String name) async {
    if (!canCreatePack) {
      throw Exception(
        'Your account does not have permission to create sound packs here.',
      );
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Sound packs need a name.');
    }
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('No active Matrix user is available.');
    }

    final now = DateTime.now().toUtc();
    final pack = SoundboardPack(
      id: _uuid.v4(),
      name: trimmedName,
      createdBy: userId,
      createdAt: now,
      updatedAt: now,
    );
    if (_routePacks) {
      final request = SoundboardAuthorityCreatePackRequest(
        requestId: pack.id,
        auth: await _authorityProof(),
        sourceSpaceId: space.identifier,
        packId: pack.id,
        name: trimmedName,
        emoji: _defaultPackEmoji,
      );
      _requireOk(
        await _runAuthorityMutation(
          operation: 'pack_create',
          requestId: request.requestId,
          send: (_) => _authority.createPack(request),
        ),
      );
      await _afterServiceMutation();
      Log.i(
        'Created soundboard pack ${pack.id} via authority in '
        '${space.identifier}',
      );
      return pack;
    }
    await _setPackState(pack);
    Log.i('Created soundboard pack ${pack.id} in ${space.identifier}');
    return pack;
  }

  @override
  Future<void> renamePack(SoundboardPack pack, String name) async {
    final userId = _currentUserId;
    if (userId == null || !canManagePack(pack, userId)) {
      throw Exception('You can only rename packs you created.');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Sound packs need a name.');
    }

    if (_routePacks) {
      final requestId = _uuid.v4();
      final proof = await _authorityProof();
      _requireOk(
        await _runAuthorityMutation(
          operation: 'pack_rename',
          requestId: requestId,
          send: (requestId) => _authority.updatePack(
            requestId: requestId,
            auth: proof,
            sourceSpaceId: space.identifier,
            packId: pack.id,
            expectedRevision: _expectedRevision(pack.revision),
            name: trimmedName,
          ),
        ),
      );
      await _afterServiceMutation();
      return;
    }
    // Renaming a derived legacy pack materializes it as explicit state under
    // its deterministic identity (KTD2).
    await _setPackState(
      pack.copyWith(name: trimmedName, updatedAt: DateTime.now().toUtc()),
    );
  }

  @override
  Future<void> setPackEmoji(SoundboardPack pack, String? emoji) async {
    final userId = _currentUserId;
    if (userId == null || !canManagePack(pack, userId)) {
      throw Exception('You can only change icons for packs you manage.');
    }
    final trimmed = emoji?.trim();
    if (_routePacks) {
      // The v1 service contract requires a non-empty emoji, so "remove icon"
      // resets protected packs to the shared default icon until clear support
      // exists service-side.
      final requestId = _uuid.v4();
      final proof = await _authorityProof();
      _requireOk(
        await _runAuthorityMutation(
          operation: 'pack_emoji',
          requestId: requestId,
          send: (requestId) => _authority.updatePack(
            requestId: requestId,
            auth: proof,
            sourceSpaceId: space.identifier,
            packId: pack.id,
            expectedRevision: _expectedRevision(pack.revision),
            emoji: trimmed != null && trimmed.isNotEmpty
                ? trimmed
                : _defaultPackEmoji,
          ),
        ),
      );
      await _afterServiceMutation();
      return;
    }
    // Same materialize-on-edit path as renamePack for a derived legacy pack.
    await _setPackState(
      pack.copyWith(
        emoji: trimmed != null && trimmed.isNotEmpty ? trimmed : null,
        clearEmoji: trimmed == null || trimmed.isEmpty,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<void> setPackEnabled(SoundboardPack pack, bool enabled) async {
    final userId = _currentUserId;
    if (userId == null || !canManagePack(pack, userId)) {
      throw Exception('You can only manage packs you created.');
    }

    if (_routePacks) {
      final requestId = _uuid.v4();
      final proof = await _authorityProof();
      _requireOk(
        await _runAuthorityMutation(
          operation: 'pack_enabled',
          requestId: requestId,
          send: (requestId) => _authority.updatePack(
            requestId: requestId,
            auth: proof,
            sourceSpaceId: space.identifier,
            packId: pack.id,
            expectedRevision: _expectedRevision(pack.revision),
            disabled: !enabled,
          ),
        ),
      );
      await _afterServiceMutation();
      return;
    }
    await _setPackState(
      pack.copyWith(enabled: enabled, updatedAt: DateTime.now().toUtc()),
    );
  }

  @override
  Future<void> setPackActive(SoundboardPack pack, bool active) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('No active Matrix user is available.');
    }

    // Merge against the latest synchronized document and store only
    // deviations from the derived default (KTD3).
    final latest = SoundboardLocalPackSettings.fromContent(
      space.matrixRoom.roomAccountData[_localPacksAccountDataKey]?.content,
    );
    final defaultActive = pack.createdBy == userId;
    final updated = latest.withOverride(
      pack.id,
      active == defaultActive ? null : active,
    );

    await client.matrixClient.setAccountDataPerRoom(
      userId,
      space.identifier,
      _localPacksAccountDataKey,
      updated.toContent(),
    );
    _localPackSettings = updated;
    _emitChanged();

    // Pairs with `soundboard event=picker_opened`: if activation is written
    // here but the picker reports a different `component`/`space_hash`, the two
    // surfaces are reading different soundboards. If they match and the picker
    // still reports the pack inactive, the override did not survive read-back.
    Log.i(
      'soundboard event=pack_activation_written result=ok '
      'pack_hash=${soundboardLogHash(pack.id)} '
      'space_hash=${soundboardLogHash(space.identifier)} '
      'component=${identityHashCode(this)} '
      'active=$active default_active=$defaultActive '
      'override_stored=${active != defaultActive} '
      'active_after=${activePackIds.contains(pack.id)} '
      'overrides=${updated.overrides.length}',
    );
  }

  @override
  Future<void> deletePack(SoundboardPack pack) async {
    final userId = _currentUserId;
    if (userId == null || !canManagePack(pack, userId)) {
      throw Exception('You can only delete packs you created.');
    }

    // Unavailable-first (KTD7): tombstone the pack before its sounds so a
    // partial failure never leaves the pack usable. Retrying re-runs only
    // the remaining sound tombstones.
    final contained = soundsInPack(pack.id);
    if (_routePacks) {
      await _deletePackViaService(pack, contained);
      return;
    }
    final alreadyTombstoned = _explicitPacks[pack.id]?.deleted ?? false;
    if (!alreadyTombstoned) {
      await _setPackState(
        pack.copyWith(
          enabled: false,
          deleted: true,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }

    var failedSounds = 0;
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final sound in contained) {
      try {
        await _setSoundState(sound.copyWith(enabled: false, deleted: true));
      } catch (error, stackTrace) {
        failedSounds++;
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (failedSounds > 0) {
      Log.onError(
        firstError!,
        firstStackTrace!,
        content:
            'Soundboard pack ${pack.id} tombstoned but $failedSounds '
            'contained sound(s) still need cleanup in ${space.identifier}',
      );
      throw Exception(
        'The pack was removed, but $failedSounds sound'
        '${failedSounds == 1 ? '' : 's'} could not be cleaned up. '
        'Delete the pack again to retry.',
      );
    }
    Log.i(
      'Deleted soundboard pack ${pack.id} and ${contained.length} sound(s) '
      'in ${space.identifier}',
    );
  }

  /// Protected-space deletion: route the pack tombstone and each contained
  /// sound through the authority service, reusing one OpenID proof. Mirrors the
  /// direct path's unavailable-first, retryable-cleanup semantics (KTD7).
  Future<void> _deletePackViaService(
    SoundboardPack pack,
    List<SoundboardSound> contained,
  ) async {
    final proof = await _authorityProof();
    final deletePackRequestId = _uuid.v4();
    _requireOk(
      await _runAuthorityMutation(
        operation: 'pack_delete',
        requestId: deletePackRequestId,
        send: (requestId) => _authority.deletePack(
          requestId: requestId,
          auth: proof,
          sourceSpaceId: space.identifier,
          packId: pack.id,
          expectedRevision: _expectedRevision(pack.revision),
        ),
      ),
    );

    var failedSounds = 0;
    SoundboardAuthorityError? firstError;
    for (final sound in contained) {
      final requestId = _uuid.v4();
      final result = await _runAuthorityMutation(
        operation: 'sound_delete',
        requestId: requestId,
        send: (requestId) => _authority.deleteSound(
          requestId: requestId,
          auth: proof,
          sourceSpaceId: space.identifier,
          soundId: sound.id,
          expectedRevision: _expectedRevision(sound.revision),
        ),
      );
      if (result case SoundboardAuthorityFailure(error: final error)) {
        failedSounds++;
        firstError ??= error;
      }
    }
    await _afterServiceMutation();

    if (failedSounds > 0) {
      Log.w(
        'soundboard event=pack_delete_partial pack_hash='
        '${soundboardLogHash(pack.id)} failed=$failedSounds '
        'code=${firstError?.code.wireValue}',
      );
      throw Exception(
        'The pack was removed, but $failedSounds sound'
        '${failedSounds == 1 ? '' : 's'} could not be cleaned up. '
        'Delete the pack again to retry.',
      );
    }
    Log.i(
      'Deleted soundboard pack ${pack.id} via authority and '
      '${contained.length} sound(s) in ${space.identifier}',
    );
  }

  @override
  Future<void> moveSoundToPack(SoundboardSound sound, String packId) async {
    final userId = _currentUserId;
    if (userId == null || !canManageSound(sound, userId)) {
      throw Exception('You can only move sounds you uploaded.');
    }
    if (effectivePackIdFor(sound) == packId) {
      return;
    }

    if (_routeSounds) {
      // Protected spaces carry explicit pack references on every service-written
      // sound, so the reference-free "legacy" clear does not arise here; the
      // move reassigns pack_id directly through the service.
      final requestId = _uuid.v4();
      final proof = await _authorityProof();
      _requireOk(
        await _runAuthorityMutation(
          operation: 'sound_move',
          requestId: requestId,
          send: (requestId) => _authority.moveSound(
            requestId: requestId,
            auth: proof,
            sourceSpaceId: space.identifier,
            soundId: sound.id,
            packId: packId,
            expectedRevision: _expectedRevision(sound.revision),
          ),
        ),
      );
      await _afterServiceMutation();
      return;
    }

    // Moving to the uploader's own legacy pack clears the reference: a
    // reference-free sound is that legacy pack's canonical membership.
    if (packId == SoundboardPack.legacyIdForUploader(sound.uploadedBy) &&
        !_explicitPacks.containsKey(packId)) {
      await _setSoundState(sound.copyWith(clearPackId: true));
      return;
    }

    final target = packById(packId);
    if (target == null || target.deleted) {
      throw Exception('That sound pack is no longer available.');
    }
    if (!canManagePack(target, userId)) {
      throw Exception('You can only move sounds into packs you manage.');
    }

    // An explicit reference to a never-materialized legacy pack would be
    // quarantined (KTD2), so materialize the target first.
    if (target.isLegacy && !_explicitPacks.containsKey(target.id)) {
      await _setPackState(target);
    }

    await _setSoundState(sound.copyWith(packId: packId));
  }

  @override
  Future<SoundboardSound> uploadSound({
    required String name,
    required String emoji,
    required Uint8List bytes,
    required String mimeType,
    int? durationMs,
    double volume = SoundboardSound.defaultVolume,
    String? packId,
  }) async {
    if (!canUploadSound) {
      throw Exception(
        'Member sound uploads are not enabled for this server yet.',
      );
    }
    if (bytes.isEmpty || bytes.length > SoundboardComponent.maxSoundBytes) {
      throw Exception('Soundboard sounds must be 2 MB or smaller.');
    }
    if (!mimeType.startsWith('audio/')) {
      throw Exception('Only audio files can be uploaded to the soundboard.');
    }

    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('No active Matrix user is available for this upload.');
    }

    // Uploading into the uploader's own legacy pack is the reference-free
    // default; other destinations must be manageable and available.
    var targetPackId = packId;
    if (targetPackId != null &&
        targetPackId == SoundboardPack.legacyIdForUploader(userId) &&
        !_explicitPacks.containsKey(targetPackId)) {
      targetPackId = null;
    }
    if (targetPackId != null) {
      final target = packById(targetPackId);
      if (target == null || target.deleted) {
        throw Exception('That sound pack is no longer available.');
      }
      if (!canManagePack(target, userId)) {
        throw Exception('You can only add sounds to packs you manage.');
      }
      if (target.isLegacy && !_explicitPacks.containsKey(target.id)) {
        await _setPackState(target);
      }
    }

    final id = _uuid.v4();
    try {
      // Media upload is a media-repo operation, not room state, so it is never
      // locked - it happens client-side in both modes.
      final url = await _uploadContentWithRetry(bytes, mimeType, id);
      if (_routeSounds) {
        final sound = await _uploadSoundViaService(
          id: id,
          userId: userId,
          name: name.trim(),
          emoji: emoji.trim(),
          url: url,
          mimeType: mimeType,
          sizeBytes: bytes.length,
          durationMs: durationMs,
          volume: SoundboardSound.normalizeVolume(volume),
          targetPackId: targetPackId,
        );
        return sound;
      }
      final sound = SoundboardSound(
        id: id,
        name: name.trim(),
        emoji: emoji.trim(),
        mxcUri: url,
        mimeType: mimeType,
        uploadedBy: userId,
        createdAt: DateTime.now().toUtc(),
        sizeBytes: bytes.length,
        durationMs: durationMs,
        volume: SoundboardSound.normalizeVolume(volume),
        packId: targetPackId,
      );

      await _setSoundState(sound);
      Log.i(
        'Uploaded soundboard sound ${sound.id} to ${space.identifier}; '
        'pack=${targetPackId ?? 'legacy'} '
        'memberUploads=$memberUploadsEnabled required=$soundUploadPowerLevel '
        'currentUser=$currentUserPowerLevel',
      );
      return sound;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to upload soundboard sound to ${space.identifier}; '
            'canUpload=$canUploadSound memberUploads=$memberUploadsEnabled '
            'required=$soundUploadPowerLevel '
            'currentUser=$currentUserPowerLevel '
            'defaultUser=$defaultUserPowerLevel',
      );
      rethrow;
    }
  }

  /// Protected-space sound creation: the media is already uploaded; register the
  /// authoritative sound state through the service, carrying the full
  /// descriptive/media payload. Every service sound belongs to a pack, so a
  /// "My sounds" (legacy) upload materializes the member's legacy pack first.
  Future<SoundboardSound> _uploadSoundViaService({
    required String id,
    required String userId,
    required String name,
    required String emoji,
    required Uri url,
    required String mimeType,
    required int sizeBytes,
    required int? durationMs,
    required double volume,
    required String? targetPackId,
  }) async {
    final proof = await _authorityProof();
    final packId = targetPackId ?? SoundboardPack.legacyIdForUploader(userId);
    // Materialize a not-yet-service-tracked target pack (e.g. the derived
    // legacy pack) so createSound has a valid pack to attach to.
    if (packById(packId)?.revision == null) {
      final request = SoundboardAuthorityCreatePackRequest(
        requestId: _uuid.v4(),
        auth: proof,
        sourceSpaceId: space.identifier,
        packId: packId,
        name: packById(packId)?.name ?? 'My sounds',
        emoji: _defaultPackEmoji,
      );
      _requireOk(
        await _runAuthorityMutation(
          operation: 'pack_materialize',
          requestId: request.requestId,
          send: (_) => _authority.createPack(request),
        ),
      );
    }
    final createSoundRequestId = _uuid.v4();
    final content = SoundboardAuthoritySoundContent(
      name: name,
      emoji: emoji,
      mxcUri: url,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      durationMs: durationMs,
      volume: volume.round(),
    );
    _requireOk(
      await _runAuthorityMutation(
        operation: 'sound_create',
        requestId: createSoundRequestId,
        send: (requestId) => _authority.createSound(
          requestId: requestId,
          auth: proof,
          sourceSpaceId: space.identifier,
          soundId: id,
          packId: packId,
          content: content,
        ),
      ),
    );
    await _afterServiceMutation();
    Log.i(
      'Uploaded soundboard sound $id via authority to ${space.identifier}; '
      'pack_hash=${soundboardLogHash(packId)}',
    );
    return SoundboardSound(
      id: id,
      name: name,
      emoji: emoji,
      mxcUri: url,
      mimeType: mimeType,
      uploadedBy: userId,
      createdAt: DateTime.now().toUtc(),
      sizeBytes: sizeBytes,
      durationMs: durationMs,
      volume: volume,
      packId: packId,
    );
  }

  static const int _uploadMaxAttempts = 3;

  /// Uploads the sound media with a bounded retry on transient network
  /// failures only. SERVER confirmed the Mini PC edge is healthy and the
  /// upload-retry QA finding is the client-side transient-network class
  /// (BUG-254/BUG-266): `Failed host lookup` and `Connection closed before full
  /// header was received`. Retrying just the media upload (not the state write)
  /// avoids re-uploading bytes or double-writing sound state, and turns a
  /// single flaky-connection blip into a transparent retry instead of a dead
  /// Upload button. Permission/validation/`M_*` errors are not transient and
  /// fail fast; exhaustion rethrows the last error so the UI shows the cause.
  Future<Uri> _uploadContentWithRetry(
    Uint8List bytes,
    String mimeType,
    String flowId,
  ) async {
    var delay = const Duration(milliseconds: 400);
    for (var attempt = 1; ; attempt++) {
      try {
        final url = await client.matrixClient.uploadContent(
          bytes,
          contentType: mimeType,
        );
        if (attempt > 1) {
          Log.i(
            'soundboard event=upload_recovered flow_id=$flowId '
            'attempt=$attempt',
          );
        }
        return url;
      } catch (error) {
        if (attempt >= _uploadMaxAttempts || !_isTransientUploadError(error)) {
          rethrow;
        }
        Log.w(
          'soundboard event=upload_retry flow_id=$flowId attempt=$attempt '
          'reason=transient_network delay_ms=${delay.inMilliseconds}',
        );
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
  }

  /// Client-side transient network failures worth a bounded retry. Mirrors the
  /// zone classifier in `Log` and the BUG-254/BUG-266 signatures; anything else
  /// (permission, quota, `M_*` Matrix errors) is treated as permanent.
  ///
  /// Best-effort substring match on the error text: brittle to message-format
  /// or locale changes, but it fails safe — an unrecognized error is treated as
  /// permanent and not retried, so at worst we fall back to the pre-retry
  /// behavior rather than retrying something that will never succeed.
  static bool _isTransientUploadError(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('socketexception: failed host lookup') ||
        normalized.contains(
          'connection closed before full header was received',
        ) ||
        normalized.contains('socketexception: connection reset') ||
        normalized.contains('socketexception: connection refused') ||
        normalized.contains('socketexception: connection timed out') ||
        normalized.contains('timeoutexception');
  }

  @override
  Future<void> updateSoundVolume(SoundboardSound sound, double volume) async {
    final userId = _currentUserId;
    if (userId == null || !canManageSound(sound, userId)) {
      throw Exception('You can only change sounds you uploaded.');
    }

    final currentSound = _availableSounds.firstWhereOrNull(
      (candidate) => candidate.id == sound.id,
    );
    if (currentSound == null) {
      throw Exception('That sound is no longer available.');
    }

    if (_routeSounds) {
      final requestId = _uuid.v4();
      final proof = await _authorityProof();
      _requireOk(
        await _runAuthorityMutation(
          operation: 'sound_volume',
          requestId: requestId,
          send: (requestId) => _authority.updateSound(
            requestId: requestId,
            auth: proof,
            sourceSpaceId: space.identifier,
            soundId: currentSound.id,
            expectedRevision: _expectedRevision(currentSound.revision),
            volume: SoundboardSound.normalizeVolume(volume).round(),
          ),
        ),
      );
      await _afterServiceMutation();
      return;
    }
    await _setSoundState(
      currentSound.copyWith(volume: SoundboardSound.normalizeVolume(volume)),
    );
  }

  @override
  Future<void> deleteSound(SoundboardSound sound) async {
    final userId = _currentUserId;
    if (userId == null || !canManageSound(sound, userId)) {
      throw Exception('You can only delete sounds you uploaded.');
    }

    if (_routeSounds) {
      final requestId = _uuid.v4();
      final proof = await _authorityProof();
      _requireOk(
        await _runAuthorityMutation(
          operation: 'sound_delete',
          requestId: requestId,
          send: (requestId) => _authority.deleteSound(
            requestId: requestId,
            auth: proof,
            sourceSpaceId: space.identifier,
            soundId: sound.id,
            expectedRevision: _expectedRevision(sound.revision),
          ),
        ),
      );
      await _afterServiceMutation();
      return;
    }
    await _setSoundState(sound.copyWith(enabled: false, deleted: true));
  }

  Future<void> _setSoundState(SoundboardSound sound) async {
    final eventId = await client.matrixClient.setRoomStateWithKey(
      space.identifier,
      SoundboardEventTypes.soundState,
      sound.id,
      sound.toStateContent(),
    );
    final event = await space.matrixRoom.getEventById(eventId);
    final states = space.matrixRoom.states.putIfAbsent(
      SoundboardEventTypes.soundState,
      () => <String, matrix.StrippedStateEvent>{},
    );
    if (event != null) {
      states[sound.id] = event;
    }
    _emitChanged();
    space.notifyUpdate();
  }

  Future<void> _setPackState(SoundboardPack pack) async {
    final eventId = await client.matrixClient.setRoomStateWithKey(
      space.identifier,
      SoundboardEventTypes.packState,
      pack.id,
      pack.toStateContent(),
    );
    final event = await space.matrixRoom.getEventById(eventId);
    final states = space.matrixRoom.states.putIfAbsent(
      SoundboardEventTypes.packState,
      () => <String, matrix.StrippedStateEvent>{},
    );
    if (event != null) {
      states[pack.id] = event;
    }
    _emitChanged();
    space.notifyUpdate();
  }

  // --- Dual-path (per-space opt-in enhanced protection) ---------------------

  /// True when this space opted into enhanced protection: the authority service
  /// wrote its config event and locked the soundboard event types
  /// (DECISIONS.md 2026-07-17). An unprotected space keeps Matrix-baseline
  /// client-managed writes.
  ///
  /// Matrix state cannot be deleted, so a disabled space keeps a lingering
  /// config event marked `enabled:false`; presence alone is not protection.
  /// Per the contract "Mode detection and the `enabled` flag":
  /// protected iff the config event is present and `enabled` is not `false`
  /// (a config written before the flag existed omits it and reads as enabled).
  @override
  bool get isProtected {
    final config = space.matrixRoom.getState(
      SoundboardEventTypes.authorityConfig,
      '',
    );
    if (config == null) {
      return false;
    }
    return config.content['enabled'] != false;
  }

  @override
  bool get supportsProtection => true;

  /// Turning protection on/off ultimately rewrites `m.room.power_levels` and the
  /// soundboard authority config, so only a space admin with that power should
  /// see the control. When the space is already protected the config type is
  /// locked at the admin level, so this still resolves true for the managing
  /// admin. The service re-verifies server-side.
  @override
  bool get canManageProtection =>
      space.matrixRoom.canChangeStateEvent(matrix.EventTypes.RoomPowerLevels) &&
      space.matrixRoom.canChangeStateEvent(
        SoundboardEventTypes.authorityConfig,
      );

  @override
  Future<void> enableProtection({int? memberUploadLevel}) async {
    final requestId = _uuid.v4();
    final proof = await _authorityProof();
    _requireOk(
      await _runAuthorityMutation(
        operation: 'protection_enable',
        requestId: requestId,
        send: (requestId) => _authority.enableSpaceProtection(
          requestId: requestId,
          auth: proof,
          sourceSpaceId: space.identifier,
          memberUploadLevel: memberUploadLevel,
        ),
      ),
    );
    await _afterServiceMutation();
  }

  @override
  Future<void> disableProtection() async {
    final requestId = _uuid.v4();
    final proof = await _authorityProof();
    _requireOk(
      await _runAuthorityMutation(
        operation: 'protection_disable',
        requestId: requestId,
        send: (requestId) => _authority.disableSpaceProtection(
          requestId: requestId,
          auth: proof,
          sourceSpaceId: space.identifier,
        ),
      ),
    );
    await _afterServiceMutation();
  }

  /// App clients route all shared mutations through the service once a space is
  /// protected. Writable soundboard state in a protected space is treated as
  /// lock drift, not permission to bypass the authority path.
  bool _routeThroughService() => isProtected;

  bool get _routePacks => _routeThroughService();
  bool get _routeSounds => _routeThroughService();

  /// The identity a service mutation acts as is decided here and nowhere else:
  /// the proof is minted from this component's own [client], so it always
  /// follows the account that owns this copy of the space. There is no
  /// "focused" or "primary" session to pick from — a space joined by two
  /// signed-in accounts yields two [MatrixSpace] objects, each with its own
  /// component and its own client, and the surface the user opened decides
  /// which one mutates. Logged (hashed, per `docs/agent-control/log-guidance.md`)
  /// so a QA report of "attributed to the wrong account" can be told apart from
  /// a genuine session-selection bug without guessing.
  Future<SoundboardAuthorityOpenIdProof> _authorityProof() async {
    final authority = _authority;
    if (authority is MatrixSoundboardAuthorityClient) {
      Log.i(
        'soundboard event=authority_proof_minted '
        'space_hash=${soundboardLogHash(space.identifier)} '
        'acting_user_hash=${soundboardLogHash(_currentUserId ?? '')} '
        'component=${identityHashCode(this)}',
      );
      return authority.currentProof();
    }
    // A non-live (test) authority client ignores the proof; supply a
    // placeholder so the call shape stays identical.
    return const SoundboardAuthorityOpenIdProof(
      matrixServerName: 'test.invalid',
      openIdToken: 'test',
    );
  }

  /// Maps a structured authority failure onto the same Exception surface the
  /// UI already handles for client-managed writes.
  Never _throwAuthority(SoundboardAuthorityError error) {
    throw Exception(
      error.message.isNotEmpty
          ? error.message
          : 'The soundboard service rejected this change (${error.code.wireValue}).',
    );
  }

  void _requireOk<T>(SoundboardAuthorityResult<T> result) {
    if (result case SoundboardAuthorityFailure(error: final error)) {
      _throwAuthority(error);
    }
  }

  /// Replays one failed protected-space mutation only when the authority
  /// service explicitly marks the response retryable. The callback receives
  /// the same [requestId] for both attempts, making a response-lost replay
  /// idempotent server-side while preserving separate IDs for separate user
  /// actions. It intentionally lives at the component call sites rather than
  /// in [MatrixSoundboardAuthorityClient]: playback authorizations and key
  /// fetches are not state mutations and must not inherit this policy.
  Future<SoundboardAuthorityResult<T>> _runAuthorityMutation<T>({
    required String operation,
    required String requestId,
    required Future<SoundboardAuthorityResult<T>> Function(String requestId)
    send,
  }) async {
    final first = await send(requestId);
    if (first case SoundboardAuthorityFailure(
      error: final error,
    ) when error.retryable) {
      Log.w(
        'soundboard event=authority_mutation_retry '
        'operation=$operation '
        'space_hash=${soundboardLogHash(space.identifier)}',
      );
      final replay = await send(requestId);
      if (replay is SoundboardAuthoritySuccess<T>) {
        Log.i(
          'soundboard event=authority_mutation_recovered '
          'operation=$operation '
          'space_hash=${soundboardLogHash(space.identifier)}',
        );
      }
      return replay;
    }
    return first;
  }

  /// Default pack icon sent when routing pack creation through the service,
  /// which requires a non-empty emoji. The user-chosen icon arrives with the
  /// pack-icons feature (separate branch); until then packs get this default.
  static const String _defaultPackEmoji = '🔊';

  /// Soundboard state event types refreshed from the server after a service
  /// mutation.
  static const Set<String> _soundboardStateTypes = {
    SoundboardEventTypes.packState,
    SoundboardEventTypes.soundState,
    SoundboardEventTypes.userState,
    SoundboardEventTypes.authorityConfig,
  };

  /// The service wrote authoritative Matrix state server-side. A local
  /// [Room.postLoad] only reloads the on-device database, which does not yet
  /// hold that write (it arrives on a later `/sync`) — so the UI would read
  /// stale content and, worse, a stale `revision`, making the next mutation
  /// send the wrong `expected_revision` and get a 409 conflict. Re-fetch the
  /// room's live state from the server and apply the soundboard events so local
  /// views converge immediately with the service-owned revision. Falls back to
  /// [Room.postLoad] if the fetch fails; the next `/sync` still converges.
  Future<void> _afterServiceMutation() async {
    try {
      final events = await client.matrixClient.getRoomState(space.identifier);
      for (final event in events) {
        if (!_soundboardStateTypes.contains(event.type)) {
          continue;
        }
        final states = space.matrixRoom.states.putIfAbsent(
          event.type,
          () => <String, matrix.StrippedStateEvent>{},
        );
        states[event.stateKey ?? ''] = event;
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Soundboard post-mutation state refresh failed for '
            '${space.identifier}',
      );
      await space.matrixRoom.postLoad();
    }
    _emitChanged();
    space.notifyUpdate();
  }

  int _expectedRevision(int? revision) => revision ?? 1;

  @override
  Future<void> setJoinSoundForUser(String userId, String? soundId) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      throw Exception('No active Matrix user is available.');
    }
    if (userId != currentUserId && !canEnableMemberUploads) {
      throw Exception('You can only set your own join sound.');
    }
    if (soundId != null && !sounds.any((sound) => sound.id == soundId)) {
      throw Exception('That sound is no longer available.');
    }

    final settings = SoundboardUserSettings(joinSoundId: soundId);
    if (userId == currentUserId) {
      await client.matrixClient.setAccountDataPerRoom(
        currentUserId,
        space.identifier,
        _joinSoundAccountDataKey,
        settings.toStateContent(),
      );
      _localJoinSoundSettings[userId] = settings;
      _emitChanged();
      return;
    }

    final eventId = await client.matrixClient.setRoomStateWithKey(
      space.identifier,
      SoundboardEventTypes.userState,
      userId,
      settings.toStateContent(),
    );
    final event = await space.matrixRoom.getEventById(eventId);
    final states = space.matrixRoom.states.putIfAbsent(
      SoundboardEventTypes.userState,
      () => <String, matrix.StrippedStateEvent>{},
    );
    if (event != null) {
      states[userId] = event;
    }
    _emitChanged();
  }

  @override
  Future<SoundboardPlayOutcome> playSound(
    SoundboardSound sound,
    Room room, {
    String source = 'manual',
    String? callSessionId,
  }) async {
    if (room is! MatrixRoom) {
      return const SoundboardPlayOutcome.refused(
        SoundboardPlayRefusal.unsupportedRoom,
        'This room cannot play soundboard sounds.',
      );
    }
    final userId = client.matrixClient.userID;
    if (userId == null) {
      return const SoundboardPlayOutcome.refused(
        SoundboardPlayRefusal.notSignedIn,
        'You are not signed in.',
      );
    }

    final nonce = _uuid.v4();

    final SoundboardPlayEvent playEvent;
    if (_ownsRoom(room)) {
      playEvent = SoundboardPlayEvent(
        soundId: sound.id,
        spaceRoomId: space.identifier,
        nonce: nonce,
        source: source,
        callSessionId: callSessionId,
      );
    } else {
      // The destination is the space the CALL belongs to, which is not
      // necessarily the space that owns the sound.
      final destinationSpaceId = _destinationSpaceIdFor(room);
      if (destinationSpaceId == null) {
        // No parent space could be resolved: not synced yet, a DM, or a room
        // with no parent at all. The destination policy cannot be consulted,
        // so there is nothing to authorize against. Falling through to the
        // same-space event would emit an unauthorized cross-space play - the
        // exact degrade-on-failure path _authorizeCrossSpacePlay refuses.
        Log.w(
          'Refusing soundboard play ${sound.id} in ${room.identifier}: '
          'destination space could not be resolved',
        );
        return const SoundboardPlayOutcome.refused(
          SoundboardPlayRefusal.destinationUnresolved,
          'That call is not in a space this sound can be played into yet.',
        );
      }
      final SoundboardPlayEvent? authorized;
      try {
        authorized = await _authorizeCrossSpacePlay(
          sound,
          room,
          destinationSpaceId: destinationSpaceId,
          callSessionId: callSessionId,
          nonce: nonce,
          source: source,
        );
      } catch (error, stackTrace) {
        // A blocked destination policy or a service refusal is an EXPECTED
        // refusal on this path, not an exception the caller must catch. Convert
        // it to an outcome carrying the reason so the picker renders it, the
        // same way a same-space refusal would be rendered.
        Log.onError(
          error,
          stackTrace,
          content: 'Cross-space soundboard play ${sound.id} refused',
        );
        return SoundboardPlayOutcome.refused(
          _crossSpaceRefusalReason(error),
          _playRefusalMessage(error),
        );
      }
      if (authorized == null) {
        // Cross-space play with no active call session: the service binds an
        // authorization to one, so it cannot be authorized at all. Previously
        // this returned null and playSound reported success, so the member saw
        // nothing happen.
        return const SoundboardPlayOutcome.refused(
          SoundboardPlayRefusal.noCallSession,
          'Join the call before playing sounds from another space.',
        );
      }
      playEvent = authorized;
    }
    await soundboardPlaybackService.playLocalAndDedupe(
      client,
      room,
      sound,
      nonce: nonce,
      senderId: userId,
      source: source,
      callSessionId: callSessionId,
      spaceRoomId: space.identifier,
    );

    try {
      Log.i(
        'Sending soundboard play ${sound.id} in ${room.identifier}; '
        'space=${space.identifier} source=$source session=${callSessionId ?? 'none'}',
      );
      final eventId = await room.matrixRoom.sendEvent(
        playEvent.toContent(),
        type: SoundboardEventTypes.play,
        displayPendingEvent: false,
      );
      if (eventId == null) {
        throw Exception('Homeserver did not accept soundboard play event.');
      }
      Log.i('Sent soundboard play ${sound.id}; event=$eventId');
    } catch (error, stackTrace) {
      // Local playback already ran, so this is not a clean refusal: the sender
      // heard it but the call did not. Reported through the same outcome channel
      // rather than thrown, so the caller has one contract to handle.
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to send soundboard play ${sound.id} in '
            '${room.identifier}',
      );
      return const SoundboardPlayOutcome.refused(
        SoundboardPlayRefusal.emissionFailed,
        'Played locally, but could not share it with the call.',
      );
    }
    return const SoundboardPlayOutcome.started();
  }

  /// Classifies a cross-space play failure into a structured refusal reason.
  ///
  /// This is a NARROWING, not an identification. The wire contract has no error
  /// code and no structured detail field that names the "the authority service
  /// cannot read the source space" condition, so it cannot be positively
  /// detected from a response today. What the service's playback handler
  /// (`createPlaybackAuthorization`) actually emits:
  ///
  /// - `forbidden` — FOUR distinct conditions, none of them this one: the
  ///   caller is not a source-space member/admin, the sound is deleted or
  ///   missing, the pack is deleted or does not match, or a legacy sound has no
  ///   uploader. Treating it as the source-space case (the previous revision
  ///   did) told a member whose sound was simply deleted to go enable sound
  ///   protection. It must never carry the hint.
  /// - `not_found` — raised on this path only by the source-space auth-state
  ///   read ("Source space is not available to the service"), which IS
  ///   consistent with the condition but does not prove it: the code is generic
  ///   and a later service change can reuse it.
  ///
  /// So `not_found` maps to [SoundboardPlayRefusal.sourceSpaceUnavailable]
  /// meaning "this MAY be a source-space setup problem", and the UI must render
  /// it as a possibility appended to the service's own message rather than as an
  /// instruction replacing it — enhanced protection is an optional space feature
  /// and must not appear in product copy as a prerequisite
  /// (`docs/DECISIONS.md`, 2026-08-08). Everything else — a client-side policy
  /// block (a plain Exception), a rate limit, an upstream outage, a malformed
  /// request — stays [SoundboardPlayRefusal.authorizationRefused].
  ///
  /// When the service grows a distinct code or a detail field naming the
  /// condition (routed to SERVER), gate on that instead and the hint can become
  /// a definite statement again.
  static SoundboardPlayRefusal _crossSpaceRefusalReason(Object error) {
    if (error is _CrossSpaceAuthorityRefusal &&
        error.error.code == SoundboardAuthorityErrorCode.notFound) {
      return SoundboardPlayRefusal.sourceSpaceUnavailable;
    }
    return SoundboardPlayRefusal.authorizationRefused;
  }

  /// A user-facing string for a thrown play refusal — the message the
  /// service/policy already put on the Exception, without the `Exception:`
  /// prefix Dart prepends.
  static String _playRefusalMessage(Object error) {
    final raw = error is Exception
        ? error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')
        : '';
    return raw.isEmpty ? 'Could not play that sound.' : raw;
  }

  void _emitChanged() {
    if (!_disposed && !_onChanged.isClosed) {
      _onChanged.add(null);
    }
  }

  Map<String, dynamic> get _powerLevelContent {
    final content = space.matrixRoom
        .getState(matrix.EventTypes.RoomPowerLevels)
        ?.content;
    return Map<String, dynamic>.from(content ?? const {});
  }

  Map<String, dynamic> _powerLevelMap(String key) {
    final value = _powerLevelContent[key];
    return Map<String, dynamic>.from(value is Map ? value : const {});
  }

  int _stateEventPowerLevel(String eventType) {
    final events = _powerLevelMap('events');
    return _powerLevelInt(
      events[eventType],
      fallback: _powerLevelInt(
        _powerLevelContent['state_default'],
        fallback: 50,
      ),
    );
  }

  int _powerLevelInt(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }
}
