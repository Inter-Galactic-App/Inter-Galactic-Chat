import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';
import 'package:intergalactic/client/matrix/components/soundboard/matrix_soundboard_authority_client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:matrix/matrix.dart' as matrix;

// The live client never touches MatrixClient except through the injected proof
// provider, so a bare stub is enough for these transport-level tests.
class _StubMatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _proof = SoundboardAuthorityOpenIdProof(
  matrixServerName: 'ourgalaxy.space',
  openIdToken: 'DUMMY_OPENID_TOKEN',
);

void main() {
  MatrixSoundboardAuthorityClient clientWith(MockClient mock) {
    return MatrixSoundboardAuthorityClient(
      client: _StubMatrixClient(),
      httpClient: mock,
      endpoint: Uri.parse(
        'https://ourgalaxy.space/api/intergalactic/soundboard/v1',
      ),
      proofProvider: (_) async => _proof,
    );
  }

  test(
    'createPack posts the OpenID proof in the body and parses the pack',
    () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'pack': {
              'schema_version': 1,
              'pack_id': 'pack-1',
              'name': 'Fixture Pack',
              'emoji': 'star',
              'creator_user_id': '@alice:ourgalaxy.space',
              'created_at': '2026-07-18T00:00:00Z',
              'updated_at': '2026-07-18T00:00:00Z',
              'updated_by': '@alice:ourgalaxy.space',
              'revision': 1,
              'disabled': false,
              'deleted': false,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = clientWith(mock);
      final result = await client.createPack(
        const SoundboardAuthorityCreatePackRequest(
          requestId: 'req-1',
          auth: _proof,
          sourceSpaceId: '!space:ourgalaxy.space',
          packId: 'pack-1',
          name: 'Fixture Pack',
          emoji: 'star',
        ),
      );

      expect(
        result,
        isA<SoundboardAuthoritySuccess<SoundboardAuthorityPackState>>(),
      );
      expect(result.valueOrNull?.packId, 'pack-1');
      expect(result.valueOrNull?.revision, 1);

      // Hits the correct endpoint...
      expect(
        captured.url.toString(),
        'https://ourgalaxy.space/api/intergalactic/soundboard/v1/packs/create',
      );
      expect(captured.method, 'POST');
      // ...and the ONLY credential in the body is the matrix_openid proof; there
      // is no long-lived Matrix access token anywhere in the request.
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['auth'], {
        'type': 'matrix_openid',
        'matrix_server_name': 'ourgalaxy.space',
        'access_token': 'DUMMY_OPENID_TOKEN',
      });
      expect(
        captured.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    },
  );

  test(
    'enableSpaceProtection posts to spaces/enable and parses the state',
    () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'protected': true,
            'source_space_id': '!space:ourgalaxy.space',
            'locked_level': 100,
            'member_upload_level': 50,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await clientWith(mock).enableSpaceProtection(
        requestId: 'req-enable',
        auth: _proof,
        sourceSpaceId: '!space:ourgalaxy.space',
        memberUploadLevel: 50,
      );

      expect(result.isOk, isTrue);
      expect(result.valueOrNull?.protectedState, isTrue);
      expect(result.valueOrNull?.lockedLevel, 100);
      expect(result.valueOrNull?.memberUploadLevel, 50);
      expect(
        captured.url.toString(),
        'https://ourgalaxy.space/api/intergalactic/soundboard/v1/spaces/enable',
      );
      expect(captured.method, 'POST');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['source_space_id'], '!space:ourgalaxy.space');
      expect(body['member_upload_level'], 50);
      // Proof-only auth (full map), no long-lived token.
      expect(body['auth'], {
        'type': 'matrix_openid',
        'matrix_server_name': 'ourgalaxy.space',
        'access_token': 'DUMMY_OPENID_TOKEN',
      });
      expect(
        captured.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    },
  );

  test('disableSpaceProtection posts to spaces/disable', () async {
    late http.Request captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'ok': true,
          'protected': false,
          'source_space_id': '!space:ourgalaxy.space',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await clientWith(mock).disableSpaceProtection(
      requestId: 'req-disable',
      auth: _proof,
      sourceSpaceId: '!space:ourgalaxy.space',
    );

    expect(result.isOk, isTrue);
    expect(result.valueOrNull?.protectedState, isFalse);
    expect(
      captured.url.toString(),
      'https://ourgalaxy.space/api/intergalactic/soundboard/v1/spaces/disable',
    );
    expect(captured.method, 'POST');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['source_space_id'], '!space:ourgalaxy.space');
    // Proof-only auth (full map), no long-lived token.
    expect(body['auth'], {
      'type': 'matrix_openid',
      'matrix_server_name': 'ourgalaxy.space',
      'access_token': 'DUMMY_OPENID_TOKEN',
    });
    expect(
      captured.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('authorization')),
    );
  });

  test('a forbidden enable surfaces the actionable service error', () async {
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {
            'code': 'forbidden',
            'message': 'Invite the service user to this space first.',
            'retryable': false,
          },
        }),
        403,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await clientWith(mock).enableSpaceProtection(
      requestId: 'req-enable-forbidden',
      auth: _proof,
      sourceSpaceId: '!space:ourgalaxy.space',
    );

    expect(result.isOk, isFalse);
    expect(result.errorOrNull?.code, SoundboardAuthorityErrorCode.forbidden);
    expect(result.errorOrNull?.message, contains('Invite the service user'));
  });

  test(
    'a conflict response maps to a structured failure with the revision',
    () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'conflict',
              'message':
                  'The soundboard pack changed before this request was applied.',
              'retryable': true,
              'current_revision': 4,
            },
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await clientWith(mock).deletePack(
        requestId: 'req-2',
        auth: _proof,
        sourceSpaceId: '!space:ourgalaxy.space',
        packId: 'pack-1',
        expectedRevision: 3,
      );

      expect(result.isOk, isFalse);
      expect(result.errorOrNull?.code, SoundboardAuthorityErrorCode.conflict);
      expect(result.errorOrNull?.currentRevision, 4);
      expect(result.errorOrNull?.retryable, isTrue);
    },
  );

  test(
    'a transport failure fails closed as retryable upstream_unavailable',
    () async {
      final mock = MockClient((request) async {
        throw http.ClientException('connection reset');
      });

      final result = await clientWith(mock).updateSound(
        requestId: 'req-3',
        auth: _proof,
        sourceSpaceId: '!space:ourgalaxy.space',
        soundId: 'sound-1',
        expectedRevision: 2,
      );

      expect(result.isOk, isFalse);
      expect(
        result.errorOrNull?.code,
        SoundboardAuthorityErrorCode.upstreamUnavailable,
      );
      expect(result.errorOrNull?.retryable, isTrue);
    },
  );

  test('a void endpoint returns success on 200', () async {
    final mock = MockClient((request) async {
      return http.Response(jsonEncode({'ok': true}), 200);
    });

    final result = await clientWith(mock).moveSound(
      requestId: 'req-4',
      auth: _proof,
      sourceSpaceId: '!space:ourgalaxy.space',
      soundId: 'sound-1',
      packId: 'pack-2',
      expectedRevision: 5,
    );

    expect(result.isOk, isTrue);
  });

  test(
    'a success body missing the pack fails closed, never a null success',
    () async {
      final mock = MockClient((request) async {
        return http.Response(jsonEncode({'ok': true}), 200);
      });

      final result = await clientWith(mock).updatePack(
        requestId: 'req-5',
        auth: _proof,
        sourceSpaceId: '!space:ourgalaxy.space',
        packId: 'pack-1',
        expectedRevision: 1,
        name: 'New name',
      );

      expect(result.isOk, isFalse);
      expect(
        result.errorOrNull?.code,
        SoundboardAuthorityErrorCode.internalError,
      );
    },
  );

  group('GET /keys', () {
    test('parses the published verification keys', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'keys': [
              {
                'kid': 'sb-2026-07',
                'algorithm': 'ed25519',
                'public_key': 'CURRENT',
                'current': true,
              },
              {
                'kid': 'sb-2026-06',
                'algorithm': 'ed25519',
                'public_key': 'PREVIOUS',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await clientWith(mock).fetchVerificationKeys();

      expect(result.isOk, isTrue);
      expect(result.valueOrNull?.map((k) => k.kid), [
        'sb-2026-07',
        'sb-2026-06',
      ]);
      expect(captured.method, 'GET');
      expect(
        captured.url.toString(),
        'https://ourgalaxy.space/api/intergalactic/soundboard/v1/keys',
      );
      // The one unauthenticated endpoint: public key material, and a receiver
      // must be able to verify without holding a credential.
      expect(captured.body, isEmpty);
      expect(
        captured.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    });

    test(
      'an empty key set fails rather than succeeding with nothing',
      () async {
        // "ok, zero keys" would let a caller mistake an unusable response for a
        // valid one; with no key, nothing can be verified.
        final mock = MockClient(
          (_) async => http.Response(jsonEncode({'keys': []}), 200),
        );

        final result = await clientWith(mock).fetchVerificationKeys();

        expect(result.isOk, isFalse);
      },
    );

    test('a malformed document fails closed', () async {
      final mock = MockClient(
        (_) async => http.Response(jsonEncode({'keys': 'nope'}), 200),
      );

      expect((await clientWith(mock).fetchVerificationKeys()).isOk, isFalse);
    });

    test('unreadable entries do not discard the readable ones', () async {
      // Rotation deliberately publishes more than one key; dropping them all
      // because one is unparseable would stop playback entirely.
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'keys': [
              'garbage',
              {'kid': 'good', 'algorithm': 'ed25519', 'public_key': 'K'},
            ],
          }),
          200,
        ),
      );

      final result = await clientWith(mock).fetchVerificationKeys();

      expect(result.valueOrNull?.map((k) => k.kid), ['good']);
    });

    test('a service error surfaces as a failure', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'upstream_unavailable',
              'message': 'Keys unavailable.',
              'retryable': true,
            },
          }),
          503,
        ),
      );

      final result = await clientWith(mock).fetchVerificationKeys();

      expect(result.isOk, isFalse);
      expect(result.errorOrNull?.retryable, isTrue);
    });
  });

  // Multi-account attribution (integration-queue 2026-07-28): the service
  // derives creator_user_id from whichever OpenID proof it receives, so the
  // account a mutation is attributed to is decided entirely by which client
  // mints the proof. These pin that the default provider mints from the client
  // it was handed and consults no ambient "primary"/"most privileged" session,
  // so a signed-in admin can never be borrowed for a member's mutation.
  group('default proof provider session selection', () {
    test('mints for the user of the client it is given', () async {
      final alice = _ProofMatrixClient('@alice:ourgalaxy.space');
      final bob = _ProofMatrixClient('@bob:ourgalaxy.space');

      final aliceProof =
          await MatrixSoundboardAuthorityClient.requestOpenIdProof(alice);
      final bobProof = await MatrixSoundboardAuthorityClient.requestOpenIdProof(
        bob,
      );

      expect(aliceProof.openIdToken, 'token-for-@alice:ourgalaxy.space');
      expect(bobProof.openIdToken, 'token-for-@bob:ourgalaxy.space');
      // Each homeserver call asked for its own user, never the other session.
      expect(alice.sdk.requestedUserIds, ['@alice:ourgalaxy.space']);
      expect(bob.sdk.requestedUserIds, ['@bob:ourgalaxy.space']);
    });

    test(
      'currentProof follows the constructing client, not the newest session',
      () async {
        final bob = _ProofMatrixClient('@bob:ourgalaxy.space');
        final authority = MatrixSoundboardAuthorityClient(
          client: bob,
          httpClient: MockClient(
            (_) async => http.Response(jsonEncode({'ok': true}), 200),
          ),
        );
        addTearDown(authority.close);

        // A second, higher-authority account signing in afterwards must not
        // change who this authority client acts as.
        final admin = _ProofMatrixClient('@admin:ourgalaxy.space');

        expect(
          (await authority.currentProof()).openIdToken,
          'token-for-@bob:ourgalaxy.space',
        );
        expect(admin.sdk.requestedUserIds, isEmpty);
      },
    );

    test(
      'a session without a user id fails loudly instead of falling back',
      () async {
        // `requestOpenIdProof` is async, so the StateError arrives as a
        // rejected Future rather than a synchronous throw. Awaited explicitly
        // so a regression that stopped throwing cannot pass as an unawaited
        // expectation.
        await expectLater(
          MatrixSoundboardAuthorityClient.requestOpenIdProof(
            _ProofMatrixClient(null),
          ),
          throwsStateError,
        );
      },
    );
  });
}

/// A [MatrixClient] whose SDK client answers OpenID token requests for exactly
/// one user, so a proof minted from the wrong session is visible in the result.
class _ProofMatrixClient implements MatrixClient {
  _ProofMatrixClient(String? userId) : sdk = _ProofSdkClient(userId);

  final _ProofSdkClient sdk;

  @override
  matrix.Client get matrixClient => sdk;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProofSdkClient implements matrix.Client {
  _ProofSdkClient(this._userId);

  final String? _userId;
  final List<String> requestedUserIds = [];

  @override
  String? get userID => _userId;

  @override
  Future<matrix.OpenIdCredentials> requestOpenIdToken(
    String userId,
    Map<String, Object?> body,
  ) async {
    requestedUserIds.add(userId);
    return matrix.OpenIdCredentials(
      accessToken: 'token-for-$userId',
      expiresIn: 3600,
      matrixServerName: 'ourgalaxy.space',
      tokenType: 'Bearer',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
