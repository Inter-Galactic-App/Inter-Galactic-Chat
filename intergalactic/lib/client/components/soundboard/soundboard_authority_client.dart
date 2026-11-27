import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_signing.dart';

/// Result of an authority call: either a decoded value or a structured service
/// error. Callers must handle both; there is no exception-based success path.
sealed class SoundboardAuthorityResult<T> {
  const SoundboardAuthorityResult();

  bool get isOk => this is SoundboardAuthoritySuccess<T>;

  /// The value on success, or null on failure. Prefer pattern-matching on the
  /// sealed subtypes; this is a convenience for call sites that only need the
  /// happy-path value.
  T? get valueOrNull => this is SoundboardAuthoritySuccess<T>
      ? (this as SoundboardAuthoritySuccess<T>).value
      : null;

  SoundboardAuthorityError? get errorOrNull =>
      this is SoundboardAuthorityFailure<T>
      ? (this as SoundboardAuthorityFailure<T>).error
      : null;
}

class SoundboardAuthoritySuccess<T> extends SoundboardAuthorityResult<T> {
  const SoundboardAuthoritySuccess(this.value);

  final T value;
}

class SoundboardAuthorityFailure<T> extends SoundboardAuthorityResult<T> {
  const SoundboardAuthorityFailure(this.error);

  final SoundboardAuthorityError error;
}

/// The client seam for the planned `soundboard-authority` service.
///
/// This is the interface the app codes against; no implementation ships in this
/// pass (the service is not deployed and the client-managed writes remain the
/// UX guard — see `docs/architecture/soundboard-authority-service-contract.md`
/// "Implementation Gate"). Every mutation authenticates with a short-lived
/// [SoundboardAuthorityOpenIdProof]; a long-lived Matrix access token must
/// never be passed to an implementation of this interface.
///
/// This covers all nine v1 endpoints: the eight client-initiated mutation and
/// issuance calls, plus `GET /keys`, which is the one unauthenticated call —
/// it returns only public verification keys and carries no proof.
///
/// Request DTOs beyond [SoundboardAuthorityCreatePackRequest] are added as each
/// endpoint is wired.
abstract interface class SoundboardAuthorityClient {
  /// `POST {pathPrefix}/spaces/enable` — admin-only. Opts a space into enhanced
  /// protection: the service writes the authority config event (`enabled:true`)
  /// and locks the pack/sound/config state event types above members. The
  /// optional [memberUploadLevel] proposes the recorded threshold (service
  /// precedence applies). Fails closed with an actionable `forbidden` /
  /// `invalid_request` error when the service user is not present or is
  /// underpowered in the space (contract "Service-presence preconditions").
  Future<SoundboardAuthorityResult<SoundboardAuthoritySpaceProtection>>
  enableSpaceProtection({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    int? memberUploadLevel,
  });

  /// `POST {pathPrefix}/spaces/disable` — admin-only. Soft-disables protection:
  /// the service overwrites the config event with `enabled:false` (preserving
  /// `member_upload_level`) BEFORE unlocking the event types, so a client never
  /// observes an unlocked space still marked enabled.
  Future<SoundboardAuthorityResult<SoundboardAuthoritySpaceProtection>>
  disableSpaceProtection({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
  });

  /// `POST {pathPrefix}/packs/create`
  Future<SoundboardAuthorityResult<SoundboardAuthorityPackState>> createPack(
    SoundboardAuthorityCreatePackRequest request,
  );

  /// `POST {pathPrefix}/packs/update` — carries `expected_revision`.
  Future<SoundboardAuthorityResult<SoundboardAuthorityPackState>> updatePack({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String packId,
    required int expectedRevision,
    String? name,
    String? emoji,
    bool? disabled,
  });

  /// `POST {pathPrefix}/packs/delete` — tombstone-first, retryable cleanup
  /// (contract "Deletion Sequencing"); carries `expected_revision`.
  Future<SoundboardAuthorityResult<SoundboardAuthorityPackState>> deletePack({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String packId,
    required int expectedRevision,
  });

  /// `POST {pathPrefix}/sounds/create` — carries the descriptive/media payload
  /// under `sound` so the service can write playable state in a protected space
  /// (contract "Fixture: Create Sound").
  Future<SoundboardAuthorityResult<void>> createSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required String packId,
    required SoundboardAuthoritySoundContent content,
  });

  /// `POST {pathPrefix}/sounds/update` — carries `expected_revision`; the
  /// optional `volume` is the only mutable descriptive field.
  Future<SoundboardAuthorityResult<void>> updateSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required int expectedRevision,
    int? volume,
  });

  /// `POST {pathPrefix}/sounds/move` — reassigns pack without re-uploading
  /// media; carries `expected_revision`.
  Future<SoundboardAuthorityResult<void>> moveSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required String packId,
    required int expectedRevision,
  });

  /// `POST {pathPrefix}/sounds/delete` — carries `expected_revision`.
  Future<SoundboardAuthorityResult<void>> deleteSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required int expectedRevision,
  });

  /// `POST {pathPrefix}/playback-authorizations/create` — returns a short-lived
  /// service-signed authorization to play one source sound into a destination
  /// call.
  Future<SoundboardAuthorityResult<SoundboardPlaybackAuthorization>>
  createPlaybackAuthorization({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String destinationRoomId,
    required String callSessionId,
    required String packId,
    required String soundId,
  });

  /// `GET {pathPrefix}/keys` — the published Ed25519 verification keys.
  ///
  /// Unauthenticated by design: the response is public key material, and a
  /// receiver must be able to verify a play without holding any credential of
  /// its own. Returns every published key, not just the current one — rotation
  /// keeps the previous key published so in-flight signatures stay verifiable.
  Future<SoundboardAuthorityResult<List<SoundboardVerificationKey>>>
  fetchVerificationKeys();
}
