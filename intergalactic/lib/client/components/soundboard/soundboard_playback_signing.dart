/// Signature canonicalization and published verification keys for cross-space
/// playback (U7).
///
/// This implements the normative "Signature Canonicalization" section of
/// `docs/architecture/soundboard-authority-service-contract.md`. It is not a
/// local invention, and it is not free to drift: a one-byte divergence from the
/// service produces no error at all, only every signature failing to verify, so
/// the rules are stated where they are implemented and pinned by a golden
/// vector taken from the service's own canonicalizer.
library;

import 'dart:convert';

import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';

/// Canonical JSON for signature coverage: object keys sorted lexicographically
/// (recursively), no insignificant whitespace, standard JSON encoding for
/// scalars. Arrays keep their order — the signed payload contains none.
///
/// The signed field set deliberately contains no floating-point values (volume
/// is not covered), which removes the usual cross-language hazard of Dart and
/// Node formatting doubles differently.
String soundboardCanonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key as String).toList()..sort();
    final entries = keys.map(
      (key) => '${jsonEncode(key)}:${soundboardCanonicalJson(value[key])}',
    );
    return '{${entries.join(',')}}';
  }
  if (value is List) {
    return '[${value.map(soundboardCanonicalJson).join(',')}]';
  }
  return jsonEncode(value);
}

extension SoundboardPlaybackAuthorizationSigning
    on SoundboardPlaybackAuthorization {
  /// The exact field set covered by the signature — `signature` itself and any
  /// transport-only fields are excluded, and no other field is covered.
  Map<String, Object?> signingPayload() => {
    'schema_version': schemaVersion,
    // Signed, so the receiver's sender check cannot be defeated by editing the
    // event. Keys are canonicalized by sort order, not by the order written
    // here, but this mirrors the contract's field list for reviewability.
    'authorized_user_id': authorizedUserId,
    'source_space_id': sourceSpaceId,
    'destination_room_id': destinationRoomId,
    'call_session_id': callSessionId,
    'pack_id': packId,
    'sound_id': soundId,
    'media': {
      'mxc_uri': media.mxcUri.toString(),
      'mime_type': media.mimeType,
      'size_bytes': media.sizeBytes,
      // OMITTED, not nulled, when the source sound has no recorded duration.
      // The service builds its media object the same way, so the key is simply
      // absent from both canonical strings. Encoding an explicit null here
      // would be unmatchable: the service's canonicalizer runs JSON.stringify
      // over a JS object, where an absent key never appears at all.
      if (media.durationMs != null) 'duration_ms': media.durationMs,
    },
    'nonce': nonce,
    // The issued string, byte for byte — see signedExpiresAt.
    'expires_at': signedExpiresAt,
    'kid': kid,
  };

  /// The UTF-8 bytes an Ed25519 verification runs over.
  List<int> signedBytes() =>
      utf8.encode(soundboardCanonicalJson(signingPayload()));
}

/// One published verification key from `GET /keys`.
class SoundboardVerificationKey {
  const SoundboardVerificationKey({
    required this.kid,
    required this.algorithm,
    required this.publicKeySpkiBase64,
    this.isCurrent = false,
  });

  static const String ed25519 = 'ed25519';

  final String kid;
  final String algorithm;

  /// SPKI DER, base64 — the shape the service publishes.
  final String publicKeySpkiBase64;
  final bool isCurrent;

  bool get isSupported => algorithm.toLowerCase() == ed25519;

  static SoundboardVerificationKey? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final kid = raw['kid'];
    final algorithm = raw['algorithm'];
    final publicKey = raw['public_key'];
    if (kid is! String ||
        kid.isEmpty ||
        algorithm is! String ||
        algorithm.isEmpty ||
        publicKey is! String ||
        publicKey.isEmpty) {
      return null;
    }
    return SoundboardVerificationKey(
      kid: kid,
      algorithm: algorithm,
      publicKeySpkiBase64: publicKey,
      isCurrent: raw['current'] == true,
    );
  }

  /// Parses a `GET /keys` document, skipping unreadable entries. A key this
  /// build cannot parse must not discard the ones it can — during a rotation
  /// the set deliberately contains more than one key, and dropping all of them
  /// would stop playback entirely.
  static List<SoundboardVerificationKey> listFromDocument(
    Map<String, dynamic>? document,
  ) {
    final raw = document?['keys'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .map(SoundboardVerificationKey.fromJson)
        .whereType<SoundboardVerificationKey>()
        .toList(growable: false);
  }
}

/// Why an authorization was refused. Every value is a refusal — there is no
/// "allowed with warnings" state, because playback is the side effect.
enum SoundboardAuthorizationFailure {
  malformed,
  expired,
  unknownKid,
  unsupportedAlgorithm,
  badSignature,
  destinationMismatch,

  /// Reserved. Was raised when the authorization's call session did not match
  /// the receiver's, but that binding is not enforceable today: session ids are
  /// per-participant and the RTC call is room-scoped (call_id ""), so the room
  /// binding covers it. Kept for a future shared per-call-instance id. See the
  /// note in SoundboardPlaybackVerifier.checkContext.
  sessionMismatch,
  soundMismatch,

  /// The play event's Matrix sender is not the user the authorization was
  /// issued to — a relayed or stolen authorization presented by someone else.
  senderMismatch,

  /// This client cannot verify cross-space authorizations at all (the base
  /// component's fail-closed default; only the Matrix implementation verifies).
  /// Distinct from [unsupportedAlgorithm], which is a real signature whose
  /// crypto algorithm this build does not support.
  unsupportedClient,
}
