import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';

/// These tests pin the client contract to the fixtures in
/// `docs/architecture/soundboard-authority-service-contract.md`. If the service
/// wire shape changes, these fail first.
void main() {
  group('SoundboardAuthorityOpenIdProof', () {
    test('serializes to the matrix_openid proof shape from the contract', () {
      const proof = SoundboardAuthorityOpenIdProof(
        matrixServerName: 'example.invalid',
        openIdToken: 'DUMMY_OPENID_TOKEN',
      );

      expect(proof.toJson(), {
        'type': 'matrix_openid',
        'matrix_server_name': 'example.invalid',
        'access_token': 'DUMMY_OPENID_TOKEN',
      });
    });

    test('round-trips through fromJson', () {
      const proof = SoundboardAuthorityOpenIdProof(
        matrixServerName: 'example.invalid',
        openIdToken: 'DUMMY_OPENID_TOKEN',
      );

      final parsed = SoundboardAuthorityOpenIdProof.fromJson(proof.toJson());

      expect(parsed, isNotNull);
      expect(parsed!.matrixServerName, 'example.invalid');
      expect(parsed.openIdToken, 'DUMMY_OPENID_TOKEN');
    });

    test('rejects any auth type other than matrix_openid', () {
      // The contract forbids sending a long-lived Matrix access token; a proof
      // must declare the OpenID type. A different type (e.g. a bearer access
      // token) must not parse into this shape.
      final parsed = SoundboardAuthorityOpenIdProof.fromJson({
        'type': 'matrix_access_token',
        'matrix_server_name': 'example.invalid',
        'access_token': 'LONG_LIVED_TOKEN',
      });

      expect(parsed, isNull);
    });

    test('the only serialized credential field is the openid proof token', () {
      // Guards the security invariant: the wire body carries exactly the
      // OpenID proof under `type: matrix_openid`, with no separate long-lived
      // token field.
      const proof = SoundboardAuthorityOpenIdProof(
        matrixServerName: 'example.invalid',
        openIdToken: 'DUMMY_OPENID_TOKEN',
      );

      final json = proof.toJson();

      expect(json.keys.toSet(), {'type', 'matrix_server_name', 'access_token'});
      expect(json['type'], 'matrix_openid');
    });

    test('rejects empty token or server name', () {
      expect(
        SoundboardAuthorityOpenIdProof.fromJson({
          'type': 'matrix_openid',
          'matrix_server_name': '',
          'access_token': 'DUMMY_OPENID_TOKEN',
        }),
        isNull,
      );
      expect(
        SoundboardAuthorityOpenIdProof.fromJson({
          'type': 'matrix_openid',
          'matrix_server_name': 'example.invalid',
          'access_token': '',
        }),
        isNull,
      );
    });
  });

  group('SoundboardAuthorityCreatePackRequest (contract fixture)', () {
    test('matches the "Fixture: Create Pack" request body', () {
      const request = SoundboardAuthorityCreatePackRequest(
        requestId: 'fixture-create-pack-0001',
        auth: SoundboardAuthorityOpenIdProof(
          matrixServerName: 'example.invalid',
          openIdToken: 'DUMMY_OPENID_TOKEN',
        ),
        sourceSpaceId: '!sourceSpace:example.invalid',
        packId: 'pack-fixture-001',
        name: 'Fixture Pack',
        emoji: 'star',
      );

      expect(request.toJson(), {
        'request_id': 'fixture-create-pack-0001',
        'auth': {
          'type': 'matrix_openid',
          'matrix_server_name': 'example.invalid',
          'access_token': 'DUMMY_OPENID_TOKEN',
        },
        'source_space_id': '!sourceSpace:example.invalid',
        'pack': {
          'pack_id': 'pack-fixture-001',
          'name': 'Fixture Pack',
          'emoji': 'star',
        },
      });
    });
  });

  group('SoundboardAuthorityPackResponse (contract fixture)', () {
    test('parses the "Fixture: Create Pack" response body', () {
      final response = SoundboardAuthorityPackResponse.fromJson({
        'ok': true,
        'pack': {
          'schema_version': 1,
          'pack_id': 'pack-fixture-001',
          'name': 'Fixture Pack',
          'emoji': 'star',
          'creator_user_id': '@alice:example.invalid',
          'created_at': '2026-07-16T00:00:00Z',
          'updated_at': '2026-07-16T00:00:00Z',
          'updated_by': '@alice:example.invalid',
          'revision': 1,
          'disabled': false,
          'deleted': false,
        },
      });

      expect(response, isNotNull);
      final pack = response!.pack;
      expect(pack.packId, 'pack-fixture-001');
      expect(pack.creatorUserId, '@alice:example.invalid');
      expect(pack.updatedBy, '@alice:example.invalid');
      expect(pack.revision, 1);
      expect(pack.disabled, isFalse);
      expect(pack.deleted, isFalse);
    });

    test('round-trips pack state', () {
      final original = SoundboardAuthorityPackState(
        schemaVersion: 1,
        packId: 'pack-fixture-001',
        name: 'Fixture Pack',
        emoji: 'star',
        creatorUserId: '@alice:example.invalid',
        createdAt: DateTime.utc(2026, 7, 16),
        updatedAt: DateTime.utc(2026, 7, 16),
        updatedBy: '@alice:example.invalid',
        revision: 1,
        disabled: false,
        deleted: false,
      );

      final parsed = SoundboardAuthorityPackState.fromJson(original.toJson());

      expect(parsed, isNotNull);
      expect(parsed!.packId, original.packId);
      expect(parsed.revision, 1);
    });

    test('defaults disabled/deleted to false when absent', () {
      final parsed = SoundboardAuthorityPackState.fromJson({
        'schema_version': 1,
        'pack_id': 'pack-fixture-001',
        'name': 'Fixture Pack',
        'emoji': 'star',
        'creator_user_id': '@alice:example.invalid',
        'created_at': '2026-07-16T00:00:00Z',
        'updated_at': '2026-07-16T00:00:00Z',
        'updated_by': '@alice:example.invalid',
        'revision': 1,
      });

      expect(parsed, isNotNull);
      expect(parsed!.disabled, isFalse);
      expect(parsed.deleted, isFalse);
    });

    test('fails closed on a present-but-malformed deleted/disabled', () {
      // A malformed `deleted` must not silently read as "not deleted".
      expect(
        SoundboardAuthorityPackState.fromJson({
          'schema_version': 1,
          'pack_id': 'pack-fixture-001',
          'name': 'Fixture Pack',
          'emoji': 'star',
          'creator_user_id': '@alice:example.invalid',
          'created_at': '2026-07-16T00:00:00Z',
          'updated_at': '2026-07-16T00:00:00Z',
          'updated_by': '@alice:example.invalid',
          'revision': 1,
          'deleted': 'yes',
        }),
        isNull,
      );
      expect(
        SoundboardAuthorityPackState.fromJson({
          'schema_version': 1,
          'pack_id': 'pack-fixture-001',
          'name': 'Fixture Pack',
          'emoji': 'star',
          'creator_user_id': '@alice:example.invalid',
          'created_at': '2026-07-16T00:00:00Z',
          'updated_at': '2026-07-16T00:00:00Z',
          'updated_by': '@alice:example.invalid',
          'revision': 1,
          'disabled': 1,
        }),
        isNull,
      );
    });

    test('rejects a revision below 1', () {
      final parsed = SoundboardAuthorityPackState.fromJson({
        'schema_version': 1,
        'pack_id': 'pack-fixture-001',
        'name': 'Fixture Pack',
        'emoji': 'star',
        'creator_user_id': '@alice:example.invalid',
        'created_at': '2026-07-16T00:00:00Z',
        'updated_at': '2026-07-16T00:00:00Z',
        'updated_by': '@alice:example.invalid',
        'revision': 0,
        'disabled': false,
        'deleted': false,
      });

      expect(parsed, isNull);
    });
  });

  group('SoundboardAuthorityError (contract fixture)', () {
    test('parses the "Fixture: Delete Pack Conflict" body with revision', () {
      final error = SoundboardAuthorityError.fromJson({
        'error': {
          'code': 'conflict',
          'message':
              'The soundboard pack changed before this request was applied.',
          'retryable': true,
          'current_revision': 4,
        },
      });

      expect(error, isNotNull);
      expect(error!.code, SoundboardAuthorityErrorCode.conflict);
      expect(error.retryable, isTrue);
      expect(error.currentRevision, 4);
    });

    test('every contract error code parses', () {
      const wireCodes = [
        'invalid_request',
        'unauthenticated',
        'forbidden',
        'not_found',
        'conflict',
        'rate_limited',
        'upstream_unavailable',
        'internal_error',
      ];

      for (final wire in wireCodes) {
        final error = SoundboardAuthorityError.fromJson({
          'error': {'code': wire, 'message': 'x', 'retryable': false},
        });
        expect(error, isNotNull, reason: wire);
        expect(error!.code.wireValue, wire);
      }
    });

    test('an unknown code maps to internal_error, never fails open', () {
      final error = SoundboardAuthorityError.fromJson({
        'error': {
          'code': 'some_future_code',
          'message': 'x',
          'retryable': false,
        },
      });

      expect(error, isNotNull);
      expect(error!.code, SoundboardAuthorityErrorCode.internalError);
    });

    test('returns null when there is no error envelope', () {
      expect(SoundboardAuthorityError.fromJson({'ok': true}), isNull);
    });
  });

  group('SoundboardPlaybackAuthorization (contract fixture)', () {
    Map<String, dynamic> fixture() => {
      'schema_version': 1,
      'authorized_user_id': '@alice:example.invalid',
      'source_space_id': '!sourceSpace:example.invalid',
      'destination_room_id': '!callRoom:example.invalid',
      'call_session_id': 'fixture-call-session',
      'pack_id': 'pack-fixture-001',
      'sound_id': 'sound-fixture-001',
      'media': {
        'mxc_uri': 'mxc://example.invalid/fixtureMedia',
        'mime_type': 'audio/ogg',
        'size_bytes': 12345,
        'duration_ms': 1200,
      },
      'nonce': 'fixture-nonce-001',
      'expires_at': '2026-07-16T00:02:00Z',
      'kid': 'sbauth-ed25519-2026-07',
      'signature': 'DUMMY_SIGNATURE',
    };

    test('parses and round-trips the contract fixture', () {
      final auth = SoundboardPlaybackAuthorization.fromJson(fixture());

      expect(auth, isNotNull);
      expect(auth!.kid, 'sbauth-ed25519-2026-07');
      expect(auth.media.mimeType, 'audio/ogg');
      expect(auth.media.sizeBytes, 12345);
      expect(
        SoundboardPlaybackAuthorization.fromJson(auth.toJson())?.signature,
        'DUMMY_SIGNATURE',
      );
    });

    test('fails closed when kid is missing (amendment 2)', () {
      final json = fixture()..remove('kid');
      expect(SoundboardPlaybackAuthorization.fromJson(json), isNull);
    });

    test('fails closed when signature is missing', () {
      final json = fixture()..remove('signature');
      expect(SoundboardPlaybackAuthorization.fromJson(json), isNull);
    });

    test('fails closed when the authorized user is missing or empty', () {
      // Required, not optional. An authorization with no issuer cannot be bound
      // to a sender, so accepting one would silently reopen the relay hole this
      // field exists to close - a pre-rebuild service response must be refused,
      // not treated as unbound.
      expect(
        SoundboardPlaybackAuthorization.fromJson(
          fixture()..remove('authorized_user_id'),
        ),
        isNull,
      );
      expect(
        SoundboardPlaybackAuthorization.fromJson(
          fixture()..['authorized_user_id'] = '',
        ),
        isNull,
      );
    });

    test('rejects media over the size bound', () {
      final json = fixture();
      (json['media'] as Map)['size_bytes'] = 999999999;
      expect(SoundboardPlaybackAuthorization.fromJson(json), isNull);
    });

    test('rejects a disallowed media mime type', () {
      final json = fixture();
      (json['media'] as Map)['mime_type'] = 'application/zip';
      expect(SoundboardPlaybackAuthorization.fromJson(json), isNull);
    });

    test('rejects an unexpected schema version', () {
      final json = fixture()..['schema_version'] = 2;
      expect(SoundboardPlaybackAuthorization.fromJson(json), isNull);
    });

    group('validity window (amendment 3)', () {
      // Fixture expires at 2026-07-16T00:02:00Z (issued 00:00, 2-minute TTL).
      final auth = SoundboardPlaybackAuthorization.fromJson({
        'schema_version': 1,
        'authorized_user_id': '@alice:example.invalid',
        'source_space_id': '!sourceSpace:example.invalid',
        'destination_room_id': '!callRoom:example.invalid',
        'call_session_id': 'fixture-call-session',
        'pack_id': 'pack-fixture-001',
        'sound_id': 'sound-fixture-001',
        'media': {
          'mxc_uri': 'mxc://example.invalid/fixtureMedia',
          'mime_type': 'audio/ogg',
          'size_bytes': 12345,
          'duration_ms': 1200,
        },
        'nonce': 'fixture-nonce-001',
        'expires_at': '2026-07-16T00:02:00Z',
        'kid': 'sbauth-ed25519-2026-07',
        'signature': 'DUMMY_SIGNATURE',
      })!;

      test('accepts a play inside the window', () {
        expect(
          auth.isWithinValidityWindow(now: DateTime.utc(2026, 7, 16, 0, 1)),
          isTrue,
        );
      });

      test('fails closed once expired beyond skew', () {
        expect(
          auth.isWithinValidityWindow(now: DateTime.utc(2026, 7, 16, 0, 2, 45)),
          isFalse,
        );
      });

      test('fails closed when the window is longer than ttl + skew', () {
        // now far before issuance makes expires_at more than ttl+skew away.
        expect(
          auth.isWithinValidityWindow(now: DateTime.utc(2026, 7, 15, 23, 55)),
          isFalse,
        );
      });
    });
  });

  group('SoundboardAuthoritySpaceProtection (contract fixture)', () {
    test('parses the "Fixture: Enable Space Protection" response', () {
      final state = SoundboardAuthoritySpaceProtection.fromJson({
        'ok': true,
        'protected': true,
        'source_space_id': '!sourceSpace:example.invalid',
        'locked_level': 100,
        'member_upload_level': 0,
      });

      expect(state, isNotNull);
      expect(state!.protectedState, isTrue);
      expect(state.sourceSpaceId, '!sourceSpace:example.invalid');
      expect(state.lockedLevel, 100);
      expect(state.memberUploadLevel, 0);
    });

    test('parses the "Fixture: Disable Space Protection" response', () {
      final state = SoundboardAuthoritySpaceProtection.fromJson({
        'ok': true,
        'protected': false,
        'source_space_id': '!sourceSpace:example.invalid',
      });

      expect(state, isNotNull);
      expect(state!.protectedState, isFalse);
      expect(state.lockedLevel, isNull);
      expect(state.memberUploadLevel, isNull);
    });

    test('fails closed on a non-ok, non-boolean, or empty-id body', () {
      // Missing ok:true never reads as a successful toggle.
      expect(
        SoundboardAuthoritySpaceProtection.fromJson({
          'protected': true,
          'source_space_id': '!s:example.invalid',
        }),
        isNull,
      );
      // A non-boolean protected value is ambiguous → reject.
      expect(
        SoundboardAuthoritySpaceProtection.fromJson({
          'ok': true,
          'protected': 'yes',
          'source_space_id': '!s:example.invalid',
        }),
        isNull,
      );
      // Empty space id → reject.
      expect(
        SoundboardAuthoritySpaceProtection.fromJson({
          'ok': true,
          'protected': true,
          'source_space_id': '',
        }),
        isNull,
      );
      // Present-but-malformed optional integers → reject.
      expect(
        SoundboardAuthoritySpaceProtection.fromJson({
          'ok': true,
          'protected': true,
          'source_space_id': '!s:example.invalid',
          'locked_level': 'high',
        }),
        isNull,
      );
    });

    test('round-trips through toJson', () {
      const state = SoundboardAuthoritySpaceProtection(
        sourceSpaceId: '!s:example.invalid',
        protectedState: true,
        lockedLevel: 100,
        memberUploadLevel: 25,
      );
      final parsed = SoundboardAuthoritySpaceProtection.fromJson(
        state.toJson(),
      );
      expect(parsed, isNotNull);
      expect(parsed!.protectedState, isTrue);
      expect(parsed.lockedLevel, 100);
      expect(parsed.memberUploadLevel, 25);
    });
  });
}
