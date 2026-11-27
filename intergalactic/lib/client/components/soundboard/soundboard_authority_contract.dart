import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';

/// Client-side wire contract for the planned `soundboard-authority` service.
///
/// Source of truth: `docs/architecture/soundboard-authority-service-contract.md`
/// (S&C approved with amendments 2026-07-17). This layer models the request,
/// response, error, and playback-authorization shapes so the app can adopt the
/// contract and SERVER has a concrete client counterpart to build against. It
/// deliberately contains no live HTTP: the existing client-managed pack/sound
/// writes remain the product/UX guard until the service is deployed and REVIEW
/// signs off (contract "Implementation Gate").
///
/// Security invariant carried by this layer: the only credential a client ever
/// sends the service is a short-lived Matrix OpenID proof
/// ([SoundboardAuthorityOpenIdProof]); a long-lived Matrix access token must
/// never reach the service. See the contract "Authentication" section.
class SoundboardAuthorityContract {
  const SoundboardAuthorityContract._();

  /// Contract version segment in `/api/intergalactic/soundboard/v1/*`.
  static const String version = 'v1';
  static const String pathPrefix = '/api/intergalactic/soundboard/v1';

  /// The only accepted client auth type: a homeserver-issued Matrix OpenID
  /// proof, never a long-lived Matrix access token.
  static const String authType = 'matrix_openid';

  static const int packSchemaVersion = 1;
  static const int playbackSchemaVersion = 1;

  /// Playback authorization validity bounds (contract amendment 3). Receivers
  /// fail closed outside these.
  static const Duration playbackSignatureTtl = Duration(minutes: 2);
  static const Duration playbackMaxClockSkew = Duration(seconds: 30);
}

/// The short-lived Matrix OpenID proof a client sends the authority service.
///
/// This is the ONLY credential the client transmits. The wire field is
/// `access_token` (the OpenID token from
/// `POST /_matrix/client/v3/user/{userId}/openid/request_token`), NOT a Matrix
/// access token. The service validates the proof through the homeserver OpenID
/// userinfo endpoint and derives the user id; the app never asserts identity
/// itself. `matrix_server_name` is subject to the service's SSRF allowlist
/// (contract amendment 1) — the client only supplies it.
class SoundboardAuthorityOpenIdProof {
  const SoundboardAuthorityOpenIdProof({
    required this.matrixServerName,
    required this.openIdToken,
  });

  final String matrixServerName;

  /// The short-lived homeserver OpenID token. Treated as a secret: never
  /// logged, never persisted, and never a long-lived Matrix access token.
  final String openIdToken;

  Map<String, dynamic> toJson() {
    return {
      'type': SoundboardAuthorityContract.authType,
      'matrix_server_name': matrixServerName,
      'access_token': openIdToken,
    };
  }

  /// Parses an auth proof, rejecting anything that is not a `matrix_openid`
  /// proof so a caller cannot smuggle a different credential type through this
  /// shape. Returns null on any malformed or non-OpenID input.
  static SoundboardAuthorityOpenIdProof? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final type = json['type'];
    final serverName = json['matrix_server_name'];
    final token = json['access_token'];
    if (type != SoundboardAuthorityContract.authType ||
        serverName is! String ||
        serverName.isEmpty ||
        token is! String ||
        token.isEmpty) {
      return null;
    }
    return SoundboardAuthorityOpenIdProof(
      matrixServerName: serverName,
      openIdToken: token,
    );
  }
}

/// Stable service error codes (contract "Error Contract").
enum SoundboardAuthorityErrorCode {
  invalidRequest('invalid_request'),
  unauthenticated('unauthenticated'),
  forbidden('forbidden'),
  notFound('not_found'),
  conflict('conflict'),
  rateLimited('rate_limited'),
  upstreamUnavailable('upstream_unavailable'),
  internalError('internal_error');

  const SoundboardAuthorityErrorCode(this.wireValue);

  final String wireValue;

  static SoundboardAuthorityErrorCode? fromWire(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final code in SoundboardAuthorityErrorCode.values) {
      if (code.wireValue == value) {
        return code;
      }
    }
    return null;
  }
}

/// A service error response body. `currentRevision` is present on `conflict`
/// (contract "Idempotency And Concurrency"): the service returns the live
/// revision, never raw state content.
class SoundboardAuthorityError {
  const SoundboardAuthorityError({
    required this.code,
    required this.message,
    required this.retryable,
    this.currentRevision,
  });

  final SoundboardAuthorityErrorCode code;
  final String message;
  final bool retryable;
  final int? currentRevision;

  Map<String, dynamic> toJson() {
    return {
      'error': {
        'code': code.wireValue,
        'message': message,
        'retryable': retryable,
        if (currentRevision != null) 'current_revision': currentRevision,
      },
    };
  }

  /// Parses `{ "error": { ... } }`. An unrecognized code maps to
  /// [SoundboardAuthorityErrorCode.internalError] so an unexpected server error
  /// never fails open into a success path. Returns null if there is no error
  /// envelope at all.
  static SoundboardAuthorityError? fromJson(Map<String, dynamic>? json) {
    final error = json?['error'];
    if (error is! Map) {
      return null;
    }
    final message = error['message'];
    final retryable = error['retryable'];
    final rawRevision = error['current_revision'];
    return SoundboardAuthorityError(
      code:
          SoundboardAuthorityErrorCode.fromWire(error['code']) ??
          SoundboardAuthorityErrorCode.internalError,
      message: message is String ? message : '',
      retryable: retryable is bool ? retryable : false,
      currentRevision: rawRevision is int ? rawRevision : null,
    );
  }
}

/// Authoritative pack state as written and returned by the service. The service
/// owns `creatorUserId`, `updatedBy`, and `revision`; clients never provide
/// authoritative values for those (contract "State Ownership").
class SoundboardAuthorityPackState {
  const SoundboardAuthorityPackState({
    required this.schemaVersion,
    required this.packId,
    required this.name,
    required this.emoji,
    required this.creatorUserId,
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    required this.revision,
    required this.disabled,
    required this.deleted,
  });

  final int schemaVersion;
  final String packId;
  final String name;
  final String emoji;
  final String creatorUserId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String updatedBy;
  final int revision;
  final bool disabled;
  final bool deleted;

  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'pack_id': packId,
      'name': name,
      'emoji': emoji,
      'creator_user_id': creatorUserId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'updated_by': updatedBy,
      'revision': revision,
      'disabled': disabled,
      'deleted': deleted,
    };
  }

  static SoundboardAuthorityPackState? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final schemaVersion = json['schema_version'];
    final packId = json['pack_id'];
    final name = json['name'];
    final emoji = json['emoji'];
    final creatorUserId = json['creator_user_id'];
    final updatedBy = json['updated_by'];
    final revision = json['revision'];
    final createdAtRaw = json['created_at'];
    final updatedAtRaw = json['updated_at'];
    if (schemaVersion is! int ||
        packId is! String ||
        packId.isEmpty ||
        name is! String ||
        emoji is! String ||
        creatorUserId is! String ||
        creatorUserId.isEmpty ||
        updatedBy is! String ||
        updatedBy.isEmpty ||
        revision is! int ||
        revision < 1 ||
        createdAtRaw is! String ||
        updatedAtRaw is! String) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (createdAt == null || updatedAt == null) {
      return null;
    }
    // `disabled`/`deleted` are optional and default false when absent, but a
    // present-but-malformed value must fail closed rather than silently read as
    // "not disabled"/"not deleted" — matching the strict parsing of every other
    // field here.
    final rawDisabled = json['disabled'];
    final rawDeleted = json['deleted'];
    if ((rawDisabled != null && rawDisabled is! bool) ||
        (rawDeleted != null && rawDeleted is! bool)) {
      return null;
    }
    return SoundboardAuthorityPackState(
      schemaVersion: schemaVersion,
      packId: packId,
      name: name,
      emoji: emoji,
      creatorUserId: creatorUserId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
      revision: revision,
      disabled: rawDisabled is bool ? rawDisabled : false,
      deleted: rawDeleted is bool ? rawDeleted : false,
    );
  }
}

/// A pack-create mutation request (contract "Fixture: Create Pack"). `requestId`
/// is the idempotency key scoped by user, source space, operation, and target
/// (contract "Idempotency And Concurrency"); the client proposes `packId` but
/// the service assigns the authoritative ownership/revision fields.
class SoundboardAuthorityCreatePackRequest {
  const SoundboardAuthorityCreatePackRequest({
    required this.requestId,
    required this.auth,
    required this.sourceSpaceId,
    required this.packId,
    required this.name,
    required this.emoji,
  });

  final String requestId;
  final SoundboardAuthorityOpenIdProof auth;
  final String sourceSpaceId;
  final String packId;
  final String name;
  final String emoji;

  Map<String, dynamic> toJson() {
    return {
      'request_id': requestId,
      'auth': auth.toJson(),
      'source_space_id': sourceSpaceId,
      'pack': {'pack_id': packId, 'name': name, 'emoji': emoji},
    };
  }
}

/// A pack mutation success response: `{ "ok": true, "pack": { ... } }`.
class SoundboardAuthorityPackResponse {
  const SoundboardAuthorityPackResponse({required this.pack});

  final SoundboardAuthorityPackState pack;

  Map<String, dynamic> toJson() => {'ok': true, 'pack': pack.toJson()};

  static SoundboardAuthorityPackResponse? fromJson(Map<String, dynamic>? json) {
    if (json == null || json['ok'] != true) {
      return null;
    }
    final packRaw = json['pack'];
    if (packRaw is! Map) {
      return null;
    }
    final pack = SoundboardAuthorityPackState.fromJson(
      Map<String, dynamic>.from(packRaw),
    );
    if (pack == null) {
      return null;
    }
    return SoundboardAuthorityPackResponse(pack: pack);
  }
}

/// The recorded protection state a space returns from `spaces/enable` and
/// `spaces/disable` (contract "Fixture: Enable/Disable Space Protection").
///
/// `protectedState` is the authoritative outcome the service reports; the room
/// state event it also writes (`chat.intergalactic.soundboard.authority` with
/// `enabled`) remains the client's steady-state detection signal. `lockedLevel`
/// and `memberUploadLevel` are only present on enable.
class SoundboardAuthoritySpaceProtection {
  const SoundboardAuthoritySpaceProtection({
    required this.sourceSpaceId,
    required this.protectedState,
    this.lockedLevel,
    this.memberUploadLevel,
  });

  final String sourceSpaceId;

  /// True once the space is opted into enhanced protection; false after a
  /// successful disable.
  final bool protectedState;

  /// The power level the pack/sound/config event types were locked to (enable
  /// only).
  final int? lockedLevel;

  /// The member upload threshold the service recorded (enable only).
  final int? memberUploadLevel;

  Map<String, dynamic> toJson() {
    return {
      'ok': true,
      'protected': protectedState,
      'source_space_id': sourceSpaceId,
      if (lockedLevel != null) 'locked_level': lockedLevel,
      if (memberUploadLevel != null) 'member_upload_level': memberUploadLevel,
    };
  }

  /// Parses `{ ok, protected, source_space_id, locked_level?, member_upload_level? }`.
  /// Fails closed (null) unless the service reported `ok:true`, a boolean
  /// `protected`, and a non-empty space id, so an ambiguous body never reads as
  /// a successful toggle. `locked_level`/`member_upload_level` are optional but
  /// must be integers when present.
  static SoundboardAuthoritySpaceProtection? fromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null || json['ok'] != true) {
      return null;
    }
    final protectedState = json['protected'];
    final sourceSpaceId = json['source_space_id'];
    final lockedLevel = json['locked_level'];
    final memberUploadLevel = json['member_upload_level'];
    if (protectedState is! bool ||
        sourceSpaceId is! String ||
        sourceSpaceId.isEmpty ||
        (lockedLevel != null && lockedLevel is! int) ||
        (memberUploadLevel != null && memberUploadLevel is! int)) {
      return null;
    }
    return SoundboardAuthoritySpaceProtection(
      sourceSpaceId: sourceSpaceId,
      protectedState: protectedState,
      lockedLevel: lockedLevel is int ? lockedLevel : null,
      memberUploadLevel: memberUploadLevel is int ? memberUploadLevel : null,
    );
  }
}

/// The descriptive/media payload a client sends with `sounds/create` (and the
/// `volume`-only subset with `sounds/update`), nested under the request's
/// `sound` field (contract "Fixture: Create Sound").
///
/// Field names match [SoundboardSound.toStateContent] exactly so the state the
/// service writes in a protected space is byte-compatible with unprotected
/// client-managed writes — [SoundboardSound.fromState] parses both identically.
/// The service owns id/uploaded_by/created_at/revision and never takes them from
/// here.
class SoundboardAuthoritySoundContent {
  const SoundboardAuthoritySoundContent({
    required this.name,
    required this.emoji,
    required this.mxcUri,
    required this.mimeType,
    required this.sizeBytes,
    this.durationMs,
    this.volume,
  });

  final String name;
  final String emoji;
  final Uri mxcUri;
  final String mimeType;
  final int sizeBytes;
  final int? durationMs;
  final int? volume;

  /// The full create payload.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'emoji': emoji,
      'url': mxcUri.toString(),
      'mimetype': mimeType,
      'size_bytes': sizeBytes,
      if (durationMs != null) 'duration_ms': durationMs,
      if (volume != null) 'volume': volume,
    };
  }

  /// The `sounds/update` subset carries only a `volume` change.
  static Map<String, dynamic> volumeOnly(int volume) => {'volume': volume};
}

/// The bounded media descriptor blessed by a playback authorization. Bounds and
/// MIME allowlist mirror [SoundboardPlaySnapshot] so a signed authorization can
/// never reference oversized or mislabeled media (contract "Rate Limiting And
/// Abuse Controls" — descriptor bounds enforced at issuance and re-checked by
/// receivers).
class SoundboardAuthorityMediaDescriptor {
  const SoundboardAuthorityMediaDescriptor({
    required this.mxcUri,
    required this.mimeType,
    required this.sizeBytes,
    this.durationMs,
  });

  final Uri mxcUri;
  final String mimeType;
  final int sizeBytes;

  /// Optional, because the app has never recorded a duration for an uploaded
  /// sound — [SoundboardSound.toStateContent] omits the field when it is null,
  /// which is every sound. Requiring it here made the descriptor unsatisfiable
  /// and every cross-space authorization fail closed at issuance.
  ///
  /// Dropping the requirement costs nothing: the value is self-asserted by the
  /// uploader, the service never inspects the media, and the real abuse bound
  /// is [SoundboardPlaySnapshot.maxSizeBytes]. When a duration IS present it is
  /// still bounds-checked.
  final int? durationMs;

  Map<String, dynamic> toJson() {
    return {
      'mxc_uri': mxcUri.toString(),
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      if (durationMs != null) 'duration_ms': durationMs,
    };
  }

  static SoundboardAuthorityMediaDescriptor? fromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    final rawUri = json['mxc_uri'];
    final mimeType = json['mime_type'];
    final sizeBytes = json['size_bytes'];
    final durationMs = json['duration_ms'];
    if (rawUri is! String ||
        mimeType is! String ||
        !SoundboardPlaySnapshot.allowedMimeTypes.contains(
          mimeType.toLowerCase(),
        ) ||
        sizeBytes is! int ||
        sizeBytes <= 0 ||
        sizeBytes > SoundboardPlaySnapshot.maxSizeBytes) {
      return null;
    }
    // Absent is fine; present-but-nonsense is not. A garbage duration would
    // otherwise be signed and then re-encoded by us, so it has to fail here.
    if (durationMs != null &&
        (durationMs is! int ||
            durationMs <= 0 ||
            durationMs > SoundboardPlaySnapshot.maxDurationMs)) {
      return null;
    }
    final mxcUri = Uri.tryParse(rawUri);
    if (mxcUri == null ||
        mxcUri.scheme != 'mxc' ||
        mxcUri.host.isEmpty ||
        mxcUri.pathSegments.isEmpty) {
      return null;
    }
    return SoundboardAuthorityMediaDescriptor(
      mxcUri: mxcUri,
      mimeType: mimeType.toLowerCase(),
      sizeBytes: sizeBytes,
      durationMs: durationMs as int?,
    );
  }
}

/// A short-lived, service-signed authorization to play one source sound into a
/// destination call (contract "Cross-Space Playback Authorization"). Receivers
/// verify `signature` against the published key named by `kid`, re-check
/// destination policy, enforce the media bounds, dedupe `nonce`, and honor the
/// validity window — failing closed on any of them.
class SoundboardPlaybackAuthorization {
  const SoundboardPlaybackAuthorization({
    required this.schemaVersion,
    required this.authorizedUserId,
    required this.sourceSpaceId,
    required this.destinationRoomId,
    required this.callSessionId,
    required this.packId,
    required this.soundId,
    required this.media,
    required this.nonce,
    required this.expiresAt,
    required this.kid,
    required this.signature,
    this.expiresAtRaw,
  });

  static final RegExp _noncePattern = RegExp(r'^[A-Za-z0-9._:-]{8,128}$');

  final int schemaVersion;

  /// The full Matrix user ID the authorization was issued to.
  ///
  /// This is INSIDE the signed field set, which is the whole point of it: an
  /// unsigned identity would be attacker-editable and would verify nothing.
  /// Receivers compare it against the play event's Matrix `sender` and fail
  /// closed on mismatch, so an authorization that is relayed, replayed, or
  /// stolen off the wire cannot be presented by anyone but the user it was
  /// issued to.
  final String authorizedUserId;
  final String sourceSpaceId;
  final String destinationRoomId;
  final String callSessionId;
  final String packId;
  final String soundId;
  final SoundboardAuthorityMediaDescriptor media;
  final String nonce;
  final DateTime expiresAt;

  /// `expires_at` EXACTLY as the service issued it, when this authorization was
  /// parsed from a service response or a transported event.
  ///
  /// The contract signs the ISO-8601 string verbatim, and re-serializing
  /// [expiresAt] can differ from it (fractional-second precision, or `+00:00`
  /// instead of `Z`). Signature verification must feed the received bytes back
  /// in unchanged, so the original is preserved here; it is null only for
  /// locally constructed instances that were never on the wire.
  final String? expiresAtRaw;

  /// The `expires_at` string to sign over: the issued one when known, else a
  /// faithful serialization of [expiresAt].
  String get signedExpiresAt =>
      expiresAtRaw ?? expiresAt.toUtc().toIso8601String();

  /// Identifies the key that produced [signature] so receivers can select the
  /// verification key from `GET /keys` (contract amendment 2). Required:
  /// receivers fail closed if it is missing or unknown.
  final String kid;
  final String signature;

  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'authorized_user_id': authorizedUserId,
      'source_space_id': sourceSpaceId,
      'destination_room_id': destinationRoomId,
      'call_session_id': callSessionId,
      'pack_id': packId,
      'sound_id': soundId,
      'media': media.toJson(),
      'nonce': nonce,
      'expires_at': signedExpiresAt,
      'kid': kid,
      'signature': signature,
    };
  }

  /// Parses an authorization payload, failing closed (null) on any malformed,
  /// out-of-bounds, or unsigned/keyless input. This does NOT verify the
  /// signature — that requires the published key and is a receiver step — but
  /// it guarantees a well-formed, `kid`-bearing, in-bounds payload before any
  /// verification is attempted.
  static SoundboardPlaybackAuthorization? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final schemaVersion = json['schema_version'];
    final authorizedUserId = json['authorized_user_id'];
    final sourceSpaceId = json['source_space_id'];
    final destinationRoomId = json['destination_room_id'];
    final callSessionId = json['call_session_id'];
    final packId = json['pack_id'];
    final soundId = json['sound_id'];
    final nonce = json['nonce'];
    final expiresAtRaw = json['expires_at'];
    final kid = json['kid'];
    final signature = json['signature'];
    final mediaRaw = json['media'];
    if (schemaVersion != SoundboardAuthorityContract.playbackSchemaVersion ||
        // Required, not optional: an authorization without an issuer cannot be
        // bound to a sender, which is exactly the hole this field closes.
        authorizedUserId is! String ||
        authorizedUserId.isEmpty ||
        sourceSpaceId is! String ||
        sourceSpaceId.isEmpty ||
        destinationRoomId is! String ||
        destinationRoomId.isEmpty ||
        callSessionId is! String ||
        callSessionId.isEmpty ||
        packId is! String ||
        packId.isEmpty ||
        soundId is! String ||
        soundId.isEmpty ||
        nonce is! String ||
        !_noncePattern.hasMatch(nonce) ||
        expiresAtRaw is! String ||
        kid is! String ||
        kid.isEmpty ||
        signature is! String ||
        signature.isEmpty ||
        mediaRaw is! Map) {
      return null;
    }
    final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
    final media = SoundboardAuthorityMediaDescriptor.fromJson(
      Map<String, dynamic>.from(mediaRaw),
    );
    if (expiresAt == null || media == null) {
      return null;
    }
    return SoundboardPlaybackAuthorization(
      schemaVersion: schemaVersion,
      authorizedUserId: authorizedUserId,
      sourceSpaceId: sourceSpaceId,
      destinationRoomId: destinationRoomId,
      callSessionId: callSessionId,
      packId: packId,
      soundId: soundId,
      media: media,
      nonce: nonce,
      expiresAt: expiresAt,
      expiresAtRaw: expiresAtRaw,
      kid: kid,
      signature: signature,
    );
  }

  /// Receiver-side validity gate (contract amendment 3). Fails closed when the
  /// authorization is already expired, or when its remaining window exceeds the
  /// signature TTL plus the allowed clock skew — bounding how long a leaked
  /// authorization stays usable regardless of what `expires_at` claims.
  bool isWithinValidityWindow({
    required DateTime now,
    Duration ttl = SoundboardAuthorityContract.playbackSignatureTtl,
    Duration maxClockSkew = SoundboardAuthorityContract.playbackMaxClockSkew,
  }) {
    final reference = now.toUtc();
    if (!expiresAt.isAfter(reference.subtract(maxClockSkew))) {
      return false;
    }
    final latestAllowedExpiry = reference.add(ttl).add(maxClockSkew);
    if (expiresAt.isAfter(latestAllowedExpiry)) {
      return false;
    }
    return true;
  }
}
