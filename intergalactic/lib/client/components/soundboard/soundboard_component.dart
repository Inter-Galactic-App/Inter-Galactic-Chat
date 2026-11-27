import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_signing.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_verifier.dart';
import 'package:intergalactic/client/components/space_component.dart';

/// Short hash for soundboard diagnostics. Room, space, user, and pack
/// identifiers must not reach logs raw (`docs/agent-control/log-guidance.md`),
/// and the redactor rewrites raw Matrix ids to one shared placeholder, which
/// would make two different spaces indistinguishable in a report. Hashing keeps
/// them comparable while staying export-safe.
String soundboardLogHash(String value) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, 12);

/// Why a [SoundboardComponent.playSound] did not fully succeed. A stable code
/// tests can assert on, so refusal tests stop matching localized [message]
/// prose that changes with copy edits.
enum SoundboardPlayRefusal {
  /// The target is not a room that can host soundboard playback.
  unsupportedRoom,

  /// No signed-in user to attribute the play to.
  notSignedIn,

  /// The call's parent space could not be resolved, so no destination policy
  /// could be consulted to authorize a cross-space play.
  destinationUnresolved,

  /// The service or the destination's external-pack policy refused to authorize
  /// the cross-space play.
  authorizationRefused,

  /// The authority service refused with a code CONSISTENT with it being unable
  /// to read the SOURCE space's state, which happens when it is not a member of
  /// that space.
  ///
  /// Deliberately weaker than the other reasons: the wire contract has no code
  /// or detail field naming that condition, so this is a narrowing rather than
  /// an identification (see `_crossSpaceRefusalReason`). Callers must keep the
  /// service's own [SoundboardPlayOutcome.message] and may add a source-space
  /// setup hint only as a possibility alongside it — never as an instruction
  /// replacing it, because the same code can also mean something the member
  /// cannot act on. Distinct from [authorizationRefused] (a blocked destination
  /// policy, a rate limit, the service being down, a caller who cannot access
  /// the source space, or a deleted sound/pack), where the hint would be
  /// straightforwardly wrong.
  sourceSpaceUnavailable,

  /// A cross-space play was attempted with no active call session to bind the
  /// authorization to.
  noCallSession,

  /// Local playback ran, but the play event could not be emitted to the call.
  emissionFailed,
}

/// The result of a [SoundboardComponent.playSound] attempt.
///
/// A refusal is an EXPECTED outcome on this path — no active call, a destination
/// that blocks external packs, a service refusal, a homeserver that rejects the
/// emission — not an exception. Every refusal returns one of these with a
/// structured [reason] and a user-facing [message] the caller renders, so the
/// picker no longer has to distinguish a thrown policy error from a silently-null
/// "no session" (which looked like success and showed the member nothing).
/// Callers that do not surface feedback (the auto join-sound path) ignore it.
class SoundboardPlayOutcome {
  const SoundboardPlayOutcome.started()
    : started = true,
      reason = null,
      message = null;
  // Both formals narrow the nullable field types on purpose: a refusal without
  // a structured reason would contradict the "null exactly when started"
  // invariant documented below, and the compiler is a better place to enforce
  // that than a code review.
  const SoundboardPlayOutcome.refused(
    SoundboardPlayRefusal this.reason,
    String this.message,
  ) : started = false;

  /// True when local playback ran and the play event was emitted.
  final bool started;

  /// The structured reason a play did not fully succeed; null exactly when
  /// [started]. Prefer asserting this over [message] in tests.
  final SoundboardPlayRefusal? reason;

  /// A short, user-facing reason the play did not fully succeed; null exactly
  /// when [started] is true.
  final String? message;
}

abstract class SoundboardComponent<R extends Client, S extends Space>
    extends SpaceComponent<R, S> {
  static const int maxSoundBytes = SoundboardConstraints.maxSoundBytes;
  static const Duration recommendedMaxDuration =
      SoundboardConstraints.recommendedMaxDuration;

  SoundboardComponent(super.client, super.space);

  /// Playable sounds: available sounds whose effective pack resolves and is
  /// itself available. Sounds carrying an explicit reference to a missing,
  /// disabled, or deleted pack are excluded (KTD2 quarantine).
  List<SoundboardSound> get sounds;

  /// Every non-deleted pack in this space: explicit pack state plus one
  /// derived legacy pack per uploader of loose (reference-free) sounds.
  /// Includes source-disabled packs so managers can re-enable them; filter
  /// with [SoundboardPack.isAvailable] for playback surfaces.
  List<SoundboardPack> get packs;

  /// Pack ids the current member has personally active in this space. Own
  /// packs are active by default; other creators' packs are inactive until
  /// enabled (R7/R8). Only available packs appear here.
  Set<String> get activePackIds;

  Stream<void> get onChanged;

  bool get canUploadSound;

  /// Whether the current member may create packs (the pack state event
  /// threshold; aligned with sound uploads per R1/KTD8).
  bool get canCreatePack;

  bool get memberUploadsEnabled;

  bool get canEnableMemberUploads;

  int get soundUploadPowerLevel;

  /// Power level required to write pack state. Existing spaces that opened
  /// sound uploads before packs shipped may need re-alignment.
  int get packCreationPowerLevel;

  int get defaultUserPowerLevel;

  int? get currentUserPowerLevel;

  String? getJoinSoundId(String userId);

  bool canManageSound(SoundboardSound sound, String userId);

  /// Creators manage their own packs; space soundboard administrators manage
  /// every pack (R2/R4).
  bool canManagePack(SoundboardPack pack, String userId);

  // -----------------------------------------------------------------------
  // Enhanced protection (per-space opt-in; service-backed). Only the live
  // Matrix component implements this; other clients report it unsupported.
  // -----------------------------------------------------------------------

  /// Whether this component can opt a space into service-backed enhanced
  /// protection at all. Gates the admin toggle so unsupported clients (e.g. the
  /// demo client) never render it.
  bool get supportsProtection => false;

  /// Whether this space currently has enhanced protection enabled (shared
  /// mutations route through the authority service).
  bool get isProtected => false;

  /// Whether the current user may turn enhanced protection on or off — a space
  /// admin able to write the soundboard config and power levels. The service
  /// re-verifies this server-side; this only decides whether to show the
  /// control.
  bool get canManageProtection => false;

  /// Opts this space into enhanced protection (admin-only). [memberUploadLevel]
  /// optionally proposes the recorded member upload threshold; the service
  /// applies its own precedence when resolving the value.
  Future<void> enableProtection({int? memberUploadLevel}) {
    throw UnsupportedError(
      'This client does not support soundboard enhanced protection.',
    );
  }

  /// Opts this space out of enhanced protection (admin-only). A soft-disable:
  /// the service marks the config disabled, then unlocks the event types.
  Future<void> disableProtection() {
    throw UnsupportedError(
      'This client does not support soundboard enhanced protection.',
    );
  }

  // -----------------------------------------------------------------------
  // Destination-space external-pack policy (U6).
  // -----------------------------------------------------------------------

  /// This space's policy on packs owned by other spaces. Absence means allow,
  /// so a space that never configured anything keeps its previous behaviour.
  SoundboardDestinationPolicy get destinationPolicy =>
      SoundboardDestinationPolicy.allowed;

  /// Whether the current user may change [destinationPolicy]. Space policy is
  /// an administrative decision, not a member preference.
  bool get canManageDestinationPolicy => false;

  Future<void> setAllowExternalPacks(bool allow) {
    throw UnsupportedError(
      'This client does not support soundboard destination policy.',
    );
  }

  /// Decides whether a cross-space play may be performed in THIS space (U7).
  ///
  /// Lives on the component rather than in the playback service so it runs
  /// against the destination space's own client: key fetching and policy are
  /// both account-scoped, and a shared verifier would reintroduce exactly the
  /// cross-account confusion this codebase has already been bitten by.
  ///
  /// Defaults to refusing. A client that cannot verify a signature must not
  /// play another space's sound.
  Future<SoundboardAuthorizationVerdict> verifyCrossSpacePlayback(
    SoundboardPlaybackAuthorization authorization, {
    required String destinationRoomId,
    required String? callSessionId,
    required String senderId,
    required String soundId,
    required String packId,
    DateTime? now,
  }) async => const SoundboardAuthorizationVerdict.refused(
    SoundboardAuthorizationFailure.unsupportedClient,
  );

  Future<void> refreshSounds();

  Future<void> enableMemberUploads();

  /// Aligns the pack state threshold with the sound-upload threshold for
  /// spaces that predate packs. Administrator-only.
  Future<void> alignPackCreationPermission();

  Future<SoundboardPack> createPack(String name);

  Future<void> renamePack(SoundboardPack pack, String name);

  /// Sets or clears the pack's icon emoji (null clears it). Like [renamePack],
  /// editing a derived legacy pack materializes it as explicit state.
  Future<void> setPackEmoji(SoundboardPack pack, String? emoji);

  /// Source-level enable/disable: affects every member's use of the pack,
  /// unlike the personal activation in [setPackActive].
  Future<void> setPackEnabled(SoundboardPack pack, bool enabled);

  /// Personal per-space activation (room account data); never changes the
  /// pack's shared state (R8).
  Future<void> setPackActive(SoundboardPack pack, bool active);

  /// Destructive: tombstones the pack first, then every contained sound, so
  /// partial failure never leaves the pack usable (KTD7). Confirmation with
  /// the contained-sound count is the caller's responsibility (R18). Safe to
  /// retry; only remaining sound tombstones are rewritten.
  Future<void> deletePack(SoundboardPack pack);

  /// Moves a sound between packs by rewriting its single pack reference; the
  /// audio is never duplicated or re-uploaded (R3).
  Future<void> moveSoundToPack(SoundboardSound sound, String packId);

  Future<SoundboardSound> uploadSound({
    required String name,
    required String emoji,
    required Uint8List bytes,
    required String mimeType,
    int? durationMs,
    double volume = SoundboardSound.defaultVolume,
    String? packId,
  });

  Future<void> updateSoundVolume(SoundboardSound sound, double volume);

  Future<void> deleteSound(SoundboardSound sound);

  Future<void> setJoinSoundForUser(String userId, String? soundId);

  /// Plays [sound] into [room]'s call and emits the play event. Returns a
  /// [SoundboardPlayOutcome]: a refusal is an ordinary result here, not a thrown
  /// error — see that type. Implementations must not throw for an expected
  /// refusal.
  Future<SoundboardPlayOutcome> playSound(
    SoundboardSound sound,
    Room room, {
    String source = 'manual',
    String? callSessionId,
  });

  // -----------------------------------------------------------------------
  // Shared pack helpers
  // -----------------------------------------------------------------------

  /// The pack a sound belongs to: its explicit reference, or its uploader's
  /// derived legacy pack when it has none.
  String effectivePackIdFor(SoundboardSound sound) =>
      sound.packId ?? SoundboardPack.legacyIdForUploader(sound.uploadedBy);

  SoundboardPack? packById(String packId) =>
      packs.firstWhereOrNull((pack) => pack.id == packId);

  bool isPackActive(SoundboardPack pack) => activePackIds.contains(pack.id);

  /// Non-deleted sounds grouped under [packId], regardless of the pack's
  /// enabled state — management and deletion counting need sounds of
  /// disabled packs too.
  List<SoundboardSound> soundsInPack(String packId);

  /// The personalized picker feed: playable sounds from the member's active
  /// packs (R9).
  List<SoundboardSound> get activeSounds {
    final active = activePackIds;
    return sounds
        .where((sound) => active.contains(effectivePackIdFor(sound)))
        .toList(growable: false);
  }

  /// Derives one legacy pack per uploader from loose sounds, skipping
  /// uploaders that already materialized their legacy pack as explicit state
  /// (KTD2).
  static List<SoundboardPack> deriveLegacyPacks(
    Iterable<SoundboardSound> looseSounds,
    Set<String> explicitPackIds,
  ) {
    final earliestByUploader = <String, DateTime>{};
    for (final sound in looseSounds) {
      if (sound.hasExplicitPackReference) {
        continue;
      }
      final current = earliestByUploader[sound.uploadedBy];
      if (current == null || sound.createdAt.isBefore(current)) {
        earliestByUploader[sound.uploadedBy] = sound.createdAt;
      }
    }

    return earliestByUploader.entries
        .where(
          (entry) => !explicitPackIds.contains(
            SoundboardPack.legacyIdForUploader(entry.key),
          ),
        )
        .map(
          (entry) => SoundboardPack.legacyForUploader(
            entry.key,
            createdAt: entry.value,
          ),
        )
        .toList(growable: false);
  }
}
