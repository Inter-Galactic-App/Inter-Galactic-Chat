/// Receiver-side verification of a signed playback authorization (U7).
///
/// A receiver may have no access to the source space at all, so it cannot
/// re-derive what the sound is. Everything it needs is in the authorization,
/// and the only reason to believe the authorization is the service signature
/// over it. That makes this the trust boundary for cross-space playback, so
/// every path here fails closed.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_signing.dart';

/// The DER prefix of an Ed25519 SubjectPublicKeyInfo. `GET /keys` publishes
/// SPKI, while Ed25519 verification takes the bare 32-byte key, so the prefix
/// is checked (not merely skipped) before the tail is used — a key of the
/// right length but the wrong algorithm must not be accepted as Ed25519.
const List<int> _ed25519SpkiPrefix = [
  0x30,
  0x2a,
  0x30,
  0x05,
  0x06,
  0x03,
  0x2b,
  0x65,
  0x70,
  0x03,
  0x21,
  0x00,
];

const int _ed25519PublicKeyLength = 32;
const int _ed25519SignatureLength = 64;

/// Extracts the raw 32-byte Ed25519 public key from a base64 SPKI document,
/// or null when it is not a well-formed Ed25519 SPKI key.
Uint8List? soundboardEd25519KeyFromSpkiBase64(String spkiBase64) {
  Uint8List der;
  try {
    der = base64.decode(spkiBase64.trim());
  } on FormatException {
    return null;
  }
  if (der.length != _ed25519SpkiPrefix.length + _ed25519PublicKeyLength) {
    return null;
  }
  for (var i = 0; i < _ed25519SpkiPrefix.length; i++) {
    if (der[i] != _ed25519SpkiPrefix[i]) {
      return null;
    }
  }
  return Uint8List.sublistView(der, _ed25519SpkiPrefix.length);
}

/// The outcome of verifying an authorization against the local context.
class SoundboardAuthorizationVerdict {
  const SoundboardAuthorizationVerdict.allowed()
    : failure = null,
      isAllowed = true;
  const SoundboardAuthorizationVerdict.refused(this.failure)
    : isAllowed = false;

  final bool isAllowed;
  final SoundboardAuthorizationFailure? failure;
}

/// Verifies signed playback authorizations against published keys.
class SoundboardPlaybackVerifier {
  SoundboardPlaybackVerifier({Ed25519? algorithm})
    : _algorithm = algorithm ?? Ed25519();

  final Ed25519 _algorithm;

  /// Checks everything about [authorization] except the signature. Split out
  /// so the cheap, deterministic rejections happen before any cryptography and
  /// before any key fetch — a mismatched destination should never cost a
  /// network round trip.
  ///
  /// [destinationRoomId] is the receiver's OWN view of the call room, and
  /// [destinationSpaceId] the receiver's own space — neither is a value taken
  /// from the event. The two are distinct on purpose: the authorization is
  /// bound to the call ROOM, while the external-pack policy is a property of
  /// the SPACE. [senderId] is the Matrix sender of the play
  /// event as the homeserver reported it — likewise not a value the event body
  /// can set. [callSessionId] is accepted but intentionally NOT gated on; see
  /// the note at the (removed) session check below. It is retained so that a
  /// shared per-call-instance identifier, if one is ever introduced, can
  /// reinstate the binding without an API change.
  SoundboardAuthorizationVerdict checkContext(
    SoundboardPlaybackAuthorization authorization, {
    required String destinationRoomId,
    required String destinationSpaceId,
    required String? callSessionId,
    required String senderId,
    required String soundId,
    required String packId,
    required SoundboardDestinationPolicy destinationPolicy,
    required DateTime now,
  }) {
    // The contract's own validity gate, not a local expiry comparison: it also
    // bounds the FORWARD window, so an authorization claiming an expiry far in
    // the future is refused rather than trusted. That caps how long a leaked
    // authorization stays usable no matter what `expires_at` says.
    if (!authorization.isWithinValidityWindow(now: now)) {
      return const SoundboardAuthorizationVerdict.refused(
        SoundboardAuthorizationFailure.expired,
      );
    }

    // The authorization is bound to one destination room. Without this a valid
    // authorization for one call could be replayed into another.
    if (authorization.destinationRoomId != destinationRoomId) {
      return const SoundboardAuthorizationVerdict.refused(
        SoundboardAuthorizationFailure.destinationMismatch,
      );
    }

    // NOT gated on the call session, deliberately. The signed
    // authorization.callSessionId is the SENDER's per-participant VoipSession id
    // (client id + room + membership state key); the receiver's own session id
    // is a different per-participant string, so an equality check here can never
    // succeed between two participants — it refused every genuine cross-space
    // play (live QA 2026-07-29, sessionMismatch on both minted sounds). There is
    // also no shared per-call-INSTANCE id to bind to instead: MatrixRTC
    // membership uses call_id "" (the call IS the room's single RTC session), so
    // the destinationRoomId binding above already provides every scope a shared
    // call id could. Replay is bounded by that room binding, the forward
    // validity window, the single-use nonce, and the sender binding below.
    // Reinstate a gate here only if a shared per-call-instance id is introduced.

    // ...and to one user. The signature covers authorized_user_id, so an
    // authorization scraped off the wire, relayed, or replayed by a third party
    // is unusable by anyone but the caller it was issued to. This is what makes
    // the plan's sender-in-session requirement enforceable without a call
    // participant roster: the service already checked the caller's source
    // access at issuance, and this pins the event to that same caller.
    if (authorization.authorizedUserId != senderId) {
      return const SoundboardAuthorizationVerdict.refused(
        SoundboardAuthorizationFailure.senderMismatch,
      );
    }

    // The event must not be able to point at a different sound than the one
    // the service authorized.
    if (authorization.soundId != soundId || authorization.packId != packId) {
      return const SoundboardAuthorizationVerdict.refused(
        SoundboardAuthorizationFailure.soundMismatch,
      );
    }

    // The destination's own policy is re-evaluated HERE, on receive, not just
    // by the sender. A signed authorization proves the service allowed it at
    // issuance; it does not bind this space's administrator, who may have
    // blocked external packs since.
    //
    // Compared against the destination SPACE, not the call room: this weighs
    // source space against destination space, and passing the room id made
    // sourceSpaceId == destinationSpaceId unreachable for any child call room,
    // so a same-space pack arriving here was always judged external.
    final evaluation = SoundboardExternalPackEvaluation.evaluate(
      sourceSpaceId: authorization.sourceSpaceId,
      destinationSpaceId: destinationSpaceId,
      destinationPolicy: destinationPolicy,
    );
    if (evaluation.isBlocked) {
      return const SoundboardAuthorizationVerdict.refused(
        SoundboardAuthorizationFailure.destinationMismatch,
      );
    }

    return const SoundboardAuthorizationVerdict.allowed();
  }

  /// Verifies the detached Ed25519 signature over the canonical payload.
  ///
  /// [keys] is the published `GET /keys` set. An unknown `kid`, an unsupported
  /// algorithm, an unusable key, or a malformed signature all refuse — a
  /// receiver never plays an authorization it could not verify.
  Future<SoundboardAuthorizationVerdict> verifySignature(
    SoundboardPlaybackAuthorization authorization, {
    required List<SoundboardVerificationKey> keys,
  }) async {
    SoundboardVerificationKey? match;
    for (final key in keys) {
      if (key.kid == authorization.kid) {
        match = key;
        break;
      }
    }
    if (match == null) {
      return const SoundboardAuthorizationVerdict.refused(
        SoundboardAuthorizationFailure.unknownKid,
      );
    }
    if (!match.isSupported) {
      return const SoundboardAuthorizationVerdict.refused(
        SoundboardAuthorizationFailure.unsupportedAlgorithm,
      );
    }

    final publicKeyBytes = soundboardEd25519KeyFromSpkiBase64(
      match.publicKeySpkiBase64,
    );
    if (publicKeyBytes == null) {
      return const SoundboardAuthorizationVerdict.refused(
        SoundboardAuthorizationFailure.unsupportedAlgorithm,
      );
    }

    Uint8List signatureBytes;
    try {
      // Standard base64 WITH padding per the contract — deliberately not
      // base64url. The nonce's alphabet is unrelated and must not be copied
      // here.
      signatureBytes = base64.decode(authorization.signature);
    } on FormatException {
      return const SoundboardAuthorizationVerdict.refused(
        SoundboardAuthorizationFailure.badSignature,
      );
    }
    if (signatureBytes.length != _ed25519SignatureLength) {
      return const SoundboardAuthorizationVerdict.refused(
        SoundboardAuthorizationFailure.badSignature,
      );
    }

    final bool verified;
    try {
      verified = await _algorithm.verify(
        authorization.signedBytes(),
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      // Any failure inside the primitive is a refusal, never a throw into the
      // playback path.
      return const SoundboardAuthorizationVerdict.refused(
        SoundboardAuthorizationFailure.badSignature,
      );
    }

    return verified
        ? const SoundboardAuthorizationVerdict.allowed()
        : const SoundboardAuthorizationVerdict.refused(
            SoundboardAuthorizationFailure.badSignature,
          );
  }
}
