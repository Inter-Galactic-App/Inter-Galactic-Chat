import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_signing.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_verifier.dart';

const _sourceSpace = '!source:ourgalaxy.space';
const _destinationSpace = '!destination:ourgalaxy.space';
const _callRoom = '!call:ourgalaxy.space';
const _session = 'session-1';
const _authorizedUser = '@alice:ourgalaxy.space';

/// INTEROP VECTOR. Regenerated 2026-07-29 after `authorized_user_id` joined the
/// signed field set, by signing the canonical payload below with a fresh
/// Ed25519 key in Node, using the DEPLOYED service's own canonicalJson +
/// signingPayload (soundboard-authority/src/signing.mjs) and node:crypto's
/// Ed25519 signer — the same path the service itself signs with.
///
/// This is the assertion that proves the whole chain interoperates: our
/// canonicalization, our SPKI parsing, and our Ed25519 verification against a
/// signature we did not produce. Everything else in this file is our own logic
/// checked against itself.
///
/// The canonical string it was signed over, for anyone re-deriving it:
/// {"authorized_user_id":"@alice:ourgalaxy.space","call_session_id":"session-1",
///  "destination_room_id":"!call:ourgalaxy.space",
///  "expires_at":"2026-07-28T00:02:00.000Z","kid":"sb-2026-07",
///  "media":{"duration_ms":1200,"mime_type":"audio/ogg",
///  "mxc_uri":"mxc://ourgalaxy.space/media","size_bytes":12345},
///  "nonce":"nonce-1","pack_id":"pack-1","schema_version":1,
///  "sound_id":"sound-1","source_space_id":"!source:ourgalaxy.space"}
const _spkiBase64 =
    'MCowBQYDK2VwAyEAHLMz7AFWIQeJgwThSZNoLJmuwucQYL/f+44jUZHCXm0=';
const _signatureBase64 =
    '+BZit7qkGWmV3mndSrALaKVlc3GHPNAr/gbUQbfaFlIDmzBdWX1t+zGQN3RysRS5clGJkUc1uneA/bBE4WVRDw==';

void main() {
  late SoundboardPlaybackVerifier verifier;

  setUp(() {
    verifier = SoundboardPlaybackVerifier();
  });

  SoundboardPlaybackAuthorization auth({
    String signature = _signatureBase64,
    String kid = 'sb-2026-07',
    String destinationRoomId = _callRoom,
    String sourceSpaceId = _sourceSpace,
    String callSessionId = _session,
    String authorizedUserId = _authorizedUser,
    String soundId = 'sound-1',
    String packId = 'pack-1',
    String expiresAt = '2026-07-28T00:02:00.000Z',
  }) => SoundboardPlaybackAuthorization(
    schemaVersion: 1,
    authorizedUserId: authorizedUserId,
    sourceSpaceId: sourceSpaceId,
    destinationRoomId: destinationRoomId,
    callSessionId: callSessionId,
    packId: packId,
    soundId: soundId,
    media: SoundboardAuthorityMediaDescriptor(
      mxcUri: Uri.parse('mxc://ourgalaxy.space/media'),
      mimeType: 'audio/ogg',
      sizeBytes: 12345,
      durationMs: 1200,
    ),
    nonce: 'nonce-1',
    expiresAt: DateTime.parse(expiresAt),
    expiresAtRaw: expiresAt,
    kid: kid,
    signature: signature,
  );

  List<SoundboardVerificationKey> keys({
    String kid = 'sb-2026-07',
    String algorithm = 'ed25519',
    String publicKey = _spkiBase64,
  }) => [
    SoundboardVerificationKey(
      kid: kid,
      algorithm: algorithm,
      publicKeySpkiBase64: publicKey,
      isCurrent: true,
    ),
  ];

  group('Ed25519 SPKI parsing', () {
    test('extracts the raw key from a published SPKI document', () {
      final key = soundboardEd25519KeyFromSpkiBase64(_spkiBase64);

      expect(key, isNotNull);
      expect(key!.length, 32);
    });

    test('rejects anything that is not a well-formed Ed25519 SPKI key', () {
      for (final candidate in [
        '',
        'not base64!!',
        // Right length, wrong algorithm prefix - must not be accepted just
        // because the tail is 32 bytes.
        'MCowBQYDK2VxAyEACni+npXqqg+5VoH6HFMQdWiAH1QJ4TfB3mxC9++F5mM=',
        // Valid base64, wrong length.
        'AAAA',
      ]) {
        expect(
          soundboardEd25519KeyFromSpkiBase64(candidate),
          isNull,
          reason: 'must reject $candidate',
        );
      }
    });
  });

  group('canonical form', () {
    test('a duration is covered by the signature when the source has one', () {
      // Pinned against the deployed service's own canonicalJson +
      // signingPayload, run over the same field values.
      expect(
        utf8.decode(auth().signedBytes()),
        '{"authorized_user_id":"@alice:ourgalaxy.space",'
        '"call_session_id":"session-1",'
        '"destination_room_id":"!call:ourgalaxy.space",'
        '"expires_at":"2026-07-28T00:02:00.000Z","kid":"sb-2026-07",'
        '"media":{"duration_ms":1200,"mime_type":"audio/ogg",'
        '"mxc_uri":"mxc://ourgalaxy.space/media","size_bytes":12345},'
        '"nonce":"nonce-1","pack_id":"pack-1","schema_version":1,'
        '"sound_id":"sound-1","source_space_id":"!source:ourgalaxy.space"}',
      );
    });

    test('an absent duration OMITS the key rather than nulling it', () {
      // The service canonicalizes a JS object: an absent key produces no
      // output, while an explicit null would produce `"duration_ms":null` and
      // `undefined` would produce literal `undefined` — not even valid JSON.
      // Only omission is reproducible on both sides, so this string is the
      // contract. Pinned against the service canonicalizer, same as above.
      final signed = auth();
      final noDuration = SoundboardPlaybackAuthorization(
        schemaVersion: signed.schemaVersion,
        authorizedUserId: signed.authorizedUserId,
        sourceSpaceId: signed.sourceSpaceId,
        destinationRoomId: signed.destinationRoomId,
        callSessionId: signed.callSessionId,
        packId: signed.packId,
        soundId: signed.soundId,
        media: SoundboardAuthorityMediaDescriptor(
          mxcUri: signed.media.mxcUri,
          mimeType: signed.media.mimeType,
          sizeBytes: signed.media.sizeBytes,
        ),
        nonce: signed.nonce,
        expiresAt: signed.expiresAt,
        expiresAtRaw: signed.expiresAtRaw,
        kid: signed.kid,
        signature: signed.signature,
      );

      expect(
        utf8.decode(noDuration.signedBytes()),
        '{"authorized_user_id":"@alice:ourgalaxy.space",'
        '"call_session_id":"session-1",'
        '"destination_room_id":"!call:ourgalaxy.space",'
        '"expires_at":"2026-07-28T00:02:00.000Z","kid":"sb-2026-07",'
        '"media":{"mime_type":"audio/ogg",'
        '"mxc_uri":"mxc://ourgalaxy.space/media","size_bytes":12345},'
        '"nonce":"nonce-1","pack_id":"pack-1","schema_version":1,'
        '"sound_id":"sound-1","source_space_id":"!source:ourgalaxy.space"}',
      );
      expect(utf8.decode(noDuration.signedBytes()), isNot(contains('null')));
      expect(
        utf8.decode(noDuration.signedBytes()),
        isNot(contains('duration_ms')),
      );
    });

    test('a media descriptor with no duration still parses', () {
      // This is the shape every sound in the app actually has: nothing has ever
      // written duration_ms into sound state, so requiring it here made every
      // cross-space authorization unissuable.
      final parsed = SoundboardAuthorityMediaDescriptor.fromJson({
        'mxc_uri': 'mxc://ourgalaxy.space/media',
        'mime_type': 'audio/ogg',
        'size_bytes': 12345,
      });

      expect(parsed, isNotNull);
      expect(parsed!.durationMs, isNull);
    });

    test('a present-but-invalid duration is still refused', () {
      for (final bad in <Object?>[0, -1, 9000, '1200', 1200.5]) {
        expect(
          SoundboardAuthorityMediaDescriptor.fromJson({
            'mxc_uri': 'mxc://ourgalaxy.space/media',
            'mime_type': 'audio/ogg',
            'size_bytes': 12345,
            'duration_ms': bad,
          }),
          isNull,
          reason: 'duration_ms $bad must fail closed',
        );
      }
    });
  });

  group('signature verification', () {
    test(
      'INTEROP: accepts a signature produced by the service signer',
      () async {
        final verdict = await verifier.verifySignature(auth(), keys: keys());

        expect(verdict.isAllowed, isTrue);
        expect(verdict.failure, isNull);
      },
    );

    test('a tampered payload no longer verifies', () async {
      // The signature covers sound_id, so swapping the sound invalidates it -
      // this is what stops a sender pointing a valid authorization at a
      // different sound.
      final verdict = await verifier.verifySignature(
        auth(soundId: 'other-sound'),
        keys: keys(),
      );

      expect(verdict.isAllowed, isFalse);
      expect(verdict.failure, SoundboardAuthorizationFailure.badSignature);
    });

    test('swapping the authorized user invalidates the signature', () async {
      // This is what makes the sender check worth anything. If the identity
      // were carried outside the signature, an attacker could simply rewrite it
      // to their own user ID and pass the context check; because it is signed,
      // rewriting it breaks verification instead.
      final verdict = await verifier.verifySignature(
        auth(authorizedUserId: '@thief:ourgalaxy.space'),
        keys: keys(),
      );

      expect(verdict.isAllowed, isFalse);
      expect(verdict.failure, SoundboardAuthorizationFailure.badSignature);
    });

    test('an unknown kid refuses rather than trying another key', () async {
      final verdict = await verifier.verifySignature(
        auth(kid: 'sb-1999-01'),
        keys: keys(),
      );

      expect(verdict.failure, SoundboardAuthorizationFailure.unknownKid);
    });

    test('a rotated-out key still verifies while it is published', () async {
      // Rotation keeps the previous key published through the overlap window
      // so in-flight signatures stay verifiable.
      final verdict = await verifier.verifySignature(
        auth(),
        keys: [
          const SoundboardVerificationKey(
            kid: 'sb-2026-08',
            algorithm: 'ed25519',
            publicKeySpkiBase64: _spkiBase64,
            isCurrent: true,
          ),
          ...keys(),
        ],
      );

      expect(verdict.isAllowed, isTrue);
    });

    test(
      'a non-Ed25519 key refuses as unsupported, not as bad signature',
      () async {
        final verdict = await verifier.verifySignature(
          auth(),
          keys: keys(algorithm: 'rsa'),
        );

        expect(
          verdict.failure,
          SoundboardAuthorizationFailure.unsupportedAlgorithm,
        );
      },
    );

    test('an unusable published key refuses instead of throwing', () async {
      final verdict = await verifier.verifySignature(
        auth(),
        keys: keys(publicKey: 'not-a-key'),
      );

      expect(
        verdict.failure,
        SoundboardAuthorizationFailure.unsupportedAlgorithm,
      );
    });

    test('a malformed or wrong-length signature refuses', () async {
      for (final signature in ['', 'not base64!!', 'AAAA']) {
        final verdict = await verifier.verifySignature(
          auth(signature: signature),
          keys: keys(),
        );
        expect(verdict.failure, SoundboardAuthorizationFailure.badSignature);
      }
    });

    test('decoding tolerates the base64url alphabet, which is harmless', () {
      // The contract specifies standard padded base64, and that is what the
      // service emits. Dart's decoder happens to accept the base64url alphabet
      // too, so an equivalent encoding decodes to the SAME 64 bytes and still
      // verifies.
      //
      // Pinned rather than "fixed": being lenient on the way in costs nothing
      // (the signature either matches those bytes or it does not), while being
      // strict would only add a way to reject valid signatures. The direction
      // that would actually be a bug - assuming base64url when the service
      // sends standard base64 - is covered by the interop test above.
      final urlEncoded = _signatureBase64
          .replaceAll('+', '-')
          .replaceAll('/', '_');
      expect(urlEncoded, isNot(_signatureBase64));

      expect(base64.decode(urlEncoded), base64.decode(_signatureBase64));
    });

    test('no published keys at all refuses', () async {
      final verdict = await verifier.verifySignature(auth(), keys: const []);

      expect(verdict.failure, SoundboardAuthorizationFailure.unknownKid);
    });
  });

  group('context checks', () {
    SoundboardAuthorizationVerdict check(
      SoundboardPlaybackAuthorization authorization, {
      String destinationRoomId = _callRoom,
      // A CHILD room of the destination space, which is the realistic shape:
      // defaulting this to the space id would hide the room-vs-space
      // distinction the policy check depends on.
      String destinationSpaceId = _destinationSpace,
      String? callSessionId = _session,
      String senderId = _authorizedUser,
      String soundId = 'sound-1',
      String packId = 'pack-1',
      SoundboardDestinationPolicy policy = SoundboardDestinationPolicy.allowed,
      DateTime? now,
    }) => verifier.checkContext(
      authorization,
      destinationRoomId: destinationRoomId,
      destinationSpaceId: destinationSpaceId,
      callSessionId: callSessionId,
      senderId: senderId,
      soundId: soundId,
      packId: packId,
      destinationPolicy: policy,
      now: now ?? DateTime.utc(2026, 7, 28),
    );

    test('a well-formed authorization for this call passes', () {
      expect(check(auth()).isAllowed, isTrue);
    });

    test('an authorization for another room is refused', () {
      // Without this, a valid authorization could be replayed into a different
      // call.
      final verdict = check(auth(destinationRoomId: '!elsewhere:x.org'));

      expect(
        verdict.failure,
        SoundboardAuthorizationFailure.destinationMismatch,
      );
    });

    test('a differing call session no longer refuses (call is room-scoped)', () {
      // The authorization's callSessionId is the SENDER's per-participant
      // session id; the receiver's is a different per-participant string, so
      // they never match between two people. With no shared per-call-instance
      // id (RTC call_id is ""), the room binding above is the real scope, so a
      // mismatched session id must NOT refuse - gating on it refused every
      // genuine cross-space play (live QA 2026-07-29).
      expect(check(auth(callSessionId: 'sender-session')).isAllowed, isTrue);
    });

    test('a null call session does not refuse here', () {
      // The "receiver must actually be in a call" guarantee lives upstream in
      // SoundboardPlaybackService (the active-session lookup), not in this
      // context check. checkContext must not itself refuse on a null session.
      expect(check(auth(), callSessionId: null).isAllowed, isTrue);
    });

    test('an authorization issued to someone else is refused', () {
      // The scenario this closes: a member of the call scrapes a valid
      // authorization off the wire (or relays one they were handed) and sends
      // it themselves. Every other field still matches this call, so the sender
      // check is the only thing standing between them and playback.
      final verdict = check(auth(), senderId: '@thief:ourgalaxy.space');

      expect(verdict.failure, SoundboardAuthorizationFailure.senderMismatch);
    });

    test('the sender check is exact, not a localpart or homeserver match', () {
      // A full Matrix user ID, per the contract - so neither a bare localpart
      // nor a same-homeserver user passes.
      for (final impostor in [
        'alice',
        '@alice:elsewhere.org',
        '@alice2:ourgalaxy.space',
        '@Alice:ourgalaxy.space',
        '',
      ]) {
        expect(
          check(auth(), senderId: impostor).failure,
          SoundboardAuthorizationFailure.senderMismatch,
          reason: 'must refuse sender $impostor',
        );
      }
    });

    test(
      'an event pointing at a different sound than the one signed is refused',
      () {
        expect(
          check(auth(), soundId: 'other').failure,
          SoundboardAuthorizationFailure.soundMismatch,
        );
        expect(
          check(auth(), packId: 'other-pack').failure,
          SoundboardAuthorizationFailure.soundMismatch,
        );
      },
    );

    test('an expired authorization is refused', () {
      final verdict = check(auth(), now: DateTime.utc(2026, 7, 28, 1));

      expect(verdict.failure, SoundboardAuthorizationFailure.expired);
    });

    test('the destination policy is re-evaluated on RECEIVE', () {
      // A signature proves the service allowed this at issuance. It does not
      // bind this space's administrator, who may have blocked external packs
      // since - so the receiver refuses even a perfectly valid authorization.
      final verdict = check(
        auth(),
        policy: const SoundboardDestinationPolicy(allowExternalPacks: false),
      );

      expect(
        verdict.failure,
        SoundboardAuthorizationFailure.destinationMismatch,
      );
    });

    test(
      'the policy weighs source space against destination SPACE, not the room',
      () {
        // REGRESSION: the destination ROOM id was passed as the destination
        // space id, so sourceSpaceId == destinationSpaceId was unreachable for
        // any child call room and a same-space pack was always judged
        // external. Here the source and destination spaces are the same, the
        // call is in a child room, and the space blocks external packs - the
        // policy must not apply at all.
        final verdict = check(
          auth(sourceSpaceId: _destinationSpace),
          policy: const SoundboardDestinationPolicy(allowExternalPacks: false),
        );

        expect(verdict.isAllowed, isTrue);
      },
    );
  });
}
