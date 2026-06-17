import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intergalactic/client/account_recovery/account_recovery_api_client.dart';

void main() {
  const proof = AccountRecoveryAuthProof(
    accessToken: 'openid-proof-token',
    matrixServerName: 'ourgalaxy.space',
  );

  test('status request uses OpenID proof headers and parses status', () async {
    final service = AccountRecoveryApiClient(
      endpoint: Uri.parse(
          'https://ourgalaxy.space/api/intergalactic/account-recovery'),
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/intergalactic/account-recovery/status');
        expect(request.headers['Authorization'], 'Bearer openid-proof-token');
        expect(request.headers['X-Matrix-Server-Name'], 'ourgalaxy.space');
        return http.Response(
          jsonEncode({
            'enabled': true,
            'user_id': '@alice:ourgalaxy.space',
            'homeserver': 'ourgalaxy.space',
            'recovery_codes': {
              'enrolled': true,
              'active_count': 8,
              'generated_at': '2026-06-02T15:00:00.000Z',
            },
            'totp': {'available': true, 'enabled': true},
            'reset': {'session_ttl_ms': 600000},
          }),
          200,
        );
      }),
    );

    final status = await service.getStatusWithProof(proof);

    expect(status.enabled, isTrue);
    expect(status.userId, '@alice:ourgalaxy.space');
    expect(status.recoveryCodes.enrolled, isTrue);
    expect(status.recoveryCodes.activeCount, 8);
    expect(status.totp.available, isTrue);
    expect(status.totp.enabled, isTrue);
    expect(status.resetSessionTtl, const Duration(minutes: 10));
  });

  test('generate recovery codes parses display-once response', () async {
    final service = AccountRecoveryApiClient(
      endpoint: Uri.parse(
          'https://ourgalaxy.space/api/intergalactic/account-recovery'),
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/intergalactic/account-recovery/recovery-codes/generate',
        );
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.headers['Accept'], 'application/json');
        expect(request.headers['Authorization'], 'Bearer openid-proof-token');
        expect(request.headers['X-Matrix-Server-Name'], 'ourgalaxy.space');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode({
            'recovery_codes': ['IG-7K2P-M9QD-R4VA'],
            'generated_at': '2026-06-02T15:00:00.000Z',
            'display_once': true,
          }),
          201,
        );
      }),
    );

    final result = await service.generateRecoveryCodesWithProof(proof);

    expect(result.codes, ['IG-7K2P-M9QD-R4VA']);
    expect(result.displayOnce, isTrue);
  });

  test('forgot-password flow posts generic start, verify, and complete bodies',
      () async {
    final seenPaths = <String>[];
    final service = AccountRecoveryApiClient(
      endpoint: Uri.parse(
          'https://ourgalaxy.space/api/intergalactic/account-recovery'),
      httpClient: MockClient((request) async {
        seenPaths.add(request.url.path);
        final body = request.body.isEmpty
            ? const <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;

        switch (request.url.path) {
          case '/api/intergalactic/account-recovery/reset/start':
            expect(body, {'username': 'alice'});
            expect(request.headers.containsKey('Authorization'), isFalse);
            return http.Response('{"accepted":true}', 202);
          case '/api/intergalactic/account-recovery/reset/verify':
            expect(body, {
              'username': 'alice',
              'factor': 'recovery_code',
              'recovery_code': 'IG-7K2P-M9QD-R4VA',
            });
            return http.Response(
              jsonEncode({
                'verified': true,
                'reset_session_token': 'reset-session-token',
                'expires_at': '2026-06-02T15:10:00.000Z',
              }),
              200,
            );
          case '/api/intergalactic/account-recovery/reset/complete':
            expect(body, {
              'reset_session_token': 'reset-session-token',
              'new_password': 'new-password',
            });
            return http.Response('{"ok":true}', 200);
        }

        return http.Response('{"error":{"code":"not_found"}}', 404);
      }),
    );

    final start = await service.startReset(username: 'alice');
    final verify = await service.verifyReset(
      username: 'alice',
      recoveryCode: 'IG-7K2P-M9QD-R4VA',
    );
    final complete = await service.completeReset(
      resetSessionToken: verify.resetSessionToken,
      newPassword: 'new-password',
    );

    expect(start.accepted, isTrue);
    expect(verify.verified, isTrue);
    expect(verify.resetSessionToken, 'reset-session-token');
    expect(complete.ok, isTrue);
    expect(seenPaths, [
      '/api/intergalactic/account-recovery/reset/start',
      '/api/intergalactic/account-recovery/reset/verify',
      '/api/intergalactic/account-recovery/reset/complete',
    ]);
  });

  test('TOTP setup, verify, and disable use OpenID proof headers', () async {
    final seenPaths = <String>[];
    final service = AccountRecoveryApiClient(
      endpoint: Uri.parse(
          'https://ourgalaxy.space/api/intergalactic/account-recovery'),
      httpClient: MockClient((request) async {
        seenPaths.add(request.url.path);
        expect(request.headers['Authorization'], 'Bearer openid-proof-token');
        expect(request.headers['X-Matrix-Server-Name'], 'ourgalaxy.space');
        final body = request.body.isEmpty
            ? const <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;

        switch (request.url.path) {
          case '/api/intergalactic/account-recovery/totp/start':
            expect(request.method, 'POST');
            expect(body, isEmpty);
            return http.Response(
              jsonEncode({
                'setup_session_token': 'totp-setup-session',
                'otpauth_uri':
                    'otpauth://totp/Inter%20Galactic:alice?secret=MANUALSECRET&issuer=Inter%20Galactic',
                'manual_secret': 'MANUALSECRET',
                'digits': 6,
                'period': 30,
                'expires_at': '2026-06-02T15:10:00.000Z',
              }),
              201,
            );
          case '/api/intergalactic/account-recovery/totp/verify':
            expect(body, {
              'setup_session_token': 'totp-setup-session',
              'otp': '123456',
            });
            return http.Response('{"ok":true,"enabled":true}', 200);
          case '/api/intergalactic/account-recovery/totp/disable':
            expect(body, {'otp': '654321'});
            return http.Response('{"ok":true,"enabled":false}', 200);
        }

        return http.Response('{"error":{"code":"not_found"}}', 404);
      }),
    );

    final setup = await service.startTotpWithProof(proof);
    final verified = await service.verifyTotpWithProof(
      proof,
      setupSessionToken: setup.setupSessionToken,
      otp: '123456',
    );
    final disabled = await service.disableTotpWithProof(proof, otp: '654321');

    expect(setup.available, isTrue);
    expect(setup.hasSetupMaterial, isTrue);
    expect(setup.setupSessionToken, 'totp-setup-session');
    expect(setup.manualSecret, 'MANUALSECRET');
    expect(setup.digits, 6);
    expect(setup.period, const Duration(seconds: 30));
    expect(verified.ok, isTrue);
    expect(verified.enabled, isTrue);
    expect(disabled.ok, isTrue);
    expect(disabled.enabled, isFalse);
    expect(seenPaths, [
      '/api/intergalactic/account-recovery/totp/start',
      '/api/intergalactic/account-recovery/totp/verify',
      '/api/intergalactic/account-recovery/totp/disable',
    ]);
  });

  test('TOTP setup returns unavailable on 501', () async {
    final service = AccountRecoveryApiClient(
      endpoint: Uri.parse(
          'https://ourgalaxy.space/api/intergalactic/account-recovery'),
      httpClient: MockClient((request) async {
        return http.Response(
          '{"error":{"code":"totp_not_enabled","message":"TOTP not enabled"}}',
          501,
        );
      }),
    );

    final result = await service.startTotpWithProof(proof);

    expect(result.available, isFalse);
  });

  test('forgot-password TOTP verification sends public factor body', () async {
    final service = AccountRecoveryApiClient(
      endpoint: Uri.parse(
          'https://ourgalaxy.space/api/intergalactic/account-recovery'),
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/intergalactic/account-recovery/reset/verify',
        );
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(jsonDecode(request.body), {
          'username': 'alice',
          'factor': 'totp',
          'otp': '123456',
        });
        return http.Response(
          jsonEncode({
            'verified': true,
            'reset_session_token': 'reset-session-token',
            'expires_at': '2026-06-02T15:10:00.000Z',
          }),
          200,
        );
      }),
    );

    final result = await service.verifyResetWithTotp(
      username: 'alice',
      otp: '123456',
    );

    expect(result.verified, isTrue);
    expect(result.resetSessionToken, 'reset-session-token');
  });

  test('throws typed exception for API errors', () async {
    final service = AccountRecoveryApiClient(
      endpoint: Uri.parse(
          'https://ourgalaxy.space/api/intergalactic/account-recovery'),
      httpClient: MockClient((request) async {
        return http.Response(
          '{"error":{"code":"invalid_recovery_factor","message":"Recovery verification failed."}}',
          400,
        );
      }),
    );

    expect(
      () => service.verifyReset(username: 'alice', recoveryCode: 'bad-code'),
      throwsA(
        isA<AccountRecoveryApiException>()
            .having((e) => e.code, 'code', 'invalid_recovery_factor')
            .having(
                (e) => e.message, 'message', 'Recovery verification failed.'),
      ),
    );
  });

  test('throws typed exception for soft reset verification failures', () async {
    final service = AccountRecoveryApiClient(
      endpoint: Uri.parse(
          'https://ourgalaxy.space/api/intergalactic/account-recovery'),
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'verified': false,
            'error': {
              'code': 'invalid_recovery_factor',
              'message': 'Recovery verification failed.',
            },
          }),
          200,
        );
      }),
    );

    expect(
      () => service.verifyReset(username: 'alice', recoveryCode: 'bad-code'),
      throwsA(
        isA<AccountRecoveryApiException>()
            .having((e) => e.statusCode, 'statusCode', 200)
            .having((e) => e.code, 'code', 'invalid_recovery_factor')
            .having(
                (e) => e.message, 'message', 'Recovery verification failed.'),
      ),
    );
  });

  test('detects allowed ourgalaxy homeserver aliases', () {
    expect(
      AccountRecoveryEligibility.isAllowedHomeserverInput('ourgalaxy.space'),
      isTrue,
    );
    expect(
      AccountRecoveryEligibility.isAllowedHomeserverInput(
        'https://matrix.ourgalaxy.space',
      ),
      isTrue,
    );
    expect(
      AccountRecoveryEligibility.isAllowedHomeserverInput('example.org'),
      isFalse,
    );
    expect(
      AccountRecoveryEligibility.isLocalMatrixUserId('@alice:ourgalaxy.space'),
      isTrue,
    );
    expect(
      AccountRecoveryEligibility.isLocalMatrixUserId(
        '@alice:matrix.ourgalaxy.space',
      ),
      isFalse,
    );
  });
}
