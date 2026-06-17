import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/debug/log_redactor.dart';
import 'package:intergalactic/debug/runtime_diagnostics_options.dart';

void main() {
  test('redacts token and password fields', () {
    final redacted = LogRedactor.redact(
      '{"access_token":"syt_secret","refresh_token":"refresh-secret",'
      '"password":"hunter2","jwt":"eyJaaaaaaaaaaa.bbbbbbbbbbbb.cccccccccccc"}',
    );

    expect(redacted, isNot(contains('syt_secret')));
    expect(redacted, isNot(contains('refresh-secret')));
    expect(redacted, isNot(contains('hunter2')));
    expect(redacted, isNot(contains('eyJaaaaaaaaaaa')));
    expect(redacted, contains('[REDACTED]'));
  });

  test('redacts authorization headers and query secrets', () {
    final redacted = LogRedactor.redact(
      'Authorization: Bearer live-secret '
      'https://matrix.example/_matrix?access_token=query-secret&via=ok',
    );

    expect(redacted, isNot(contains('live-secret')));
    expect(redacted, isNot(contains('query-secret')));
    expect(redacted, contains('access_token=[REDACTED]'));
  });

  test('redacts signed CDN query fields', () {
    final redacted = LogRedactor.redact(
      'https://p16-common-sign.tiktokcdn-us.com/obj/demo.jpeg'
      '?x-expires=1700000000&x-signature=tiktok-signature&format=jpeg '
      'https://scontent.cdninstagram.com/v/t51.29350/demo.jpg'
      '?stp=dst-jpg&_nc_ohc=instagram-secret&oh=signed-hash&oe=expiry',
    );

    expect(redacted, isNot(contains('tiktok-signature')));
    expect(redacted, isNot(contains('instagram-secret')));
    expect(redacted, isNot(contains('signed-hash')));
    expect(redacted, contains('x-signature=[REDACTED]'));
    expect(redacted, contains('_nc_ohc=[REDACTED]'));
    expect(redacted, contains('format=jpeg'));
  });

  test('redacts JSON authorization and camelCase token fields', () {
    final redacted = LogRedactor.redact(
      '{"Authorization":"Bearer json-secret",'
      '"accessToken":"camel-secret",'
      '"refreshToken":"refresh-secret"} '
      'Proxy-Authorization: Basic proxy-secret',
    );

    expect(redacted, isNot(contains('json-secret')));
    expect(redacted, isNot(contains('camel-secret')));
    expect(redacted, isNot(contains('refresh-secret')));
    expect(redacted, isNot(contains('proxy-secret')));
    expect(redacted, contains('[REDACTED]'));
  });

  test('redacts push tokens and labelled push keys', () {
    const fcmToken =
        'fcmRegistration:APA91bFakeFirebaseTokenValueWithEnoughLengthToLookLikeARealPushToken1234567890';
    final redacted = LogRedactor.redactForBugReport(
      'Current push key: $fcmToken '
      '{"fcm_token":"$fcmToken","device_token":"device-secret-value"} '
      'push_key=$fcmToken '
      'https://example.invalid/push?push_key=$fcmToken',
    );

    expect(redacted, isNot(contains(fcmToken)));
    expect(redacted, isNot(contains('device-secret-value')));
    expect(redacted, contains('Current push key: [REDACTED]'));
    expect(redacted, contains('push_key=[REDACTED]'));
  });

  test('redacts dynamic secrets exactly', () {
    final redacted = LogRedactor.redact(
      'Matrix request used local-token-value',
      dynamicSecrets: const ['local-token-value'],
    );

    expect(redacted, isNot(contains('local-token-value')));
  });

  test('bug report redaction removes cookies, local paths, emails, and keys',
      () {
    final fixtureRoot = _windowsFixtureRoot;
    final redacted = LogRedactor.redactForBugReport(
      r'Cookie: sid=abc123; path=/ '
      '\n'
      r'session_key=megolm-secret '
      r'crypto_secret=ssss '
      '$fixtureRoot'
      r'\AppData\Local\secret.txt '
      'reporter@example.com',
    );

    expect(redacted, isNot(contains('sid=abc123')));
    expect(redacted, isNot(contains('megolm-secret')));
    expect(redacted, isNot(contains('ssss')));
    expect(redacted, isNot(contains(fixtureRoot)));
    expect(redacted, isNot(contains('reporter@example.com')));
    expect(redacted, contains('[LOCAL_PATH]/secret.txt'));
  });

  test('bug report redaction can preserve intentional contact emails', () {
    final redacted = LogRedactor.redactForBugReport(
      'Contact me at reporter@example.com with access_token=secret',
      redactEmails: false,
    );

    expect(redacted, contains('reporter@example.com'));
    expect(redacted, isNot(contains('secret')));
  });

  test('redacts recovery-key-like strings outside structured fields', () {
    final redacted = LogRedactor.redact(
      'Matrix recovery key is ABCD EFGH IJKM NPQR STUV WXYZ 1234 5678. '
      'Free text key ABCD-EFGH-IJKM-NPQR-STUV-WXYZ-1234-5678 appeared.',
    );

    expect(redacted, isNot(contains('ABCD EFGH')));
    expect(redacted, isNot(contains('ABCD-EFGH')));
    expect(redacted, contains('[REDACTED]'));
  });

  test('redacts Matrix identifiers and MXC URIs', () {
    final redacted = LogRedactor.redact(
      r'user @alice:example.org room !abcdef123456:example.org '
      r'alias #ops:example.org event $eventidentifier123:example.org '
      r'sender=@sender:example.org room_id=!roomidentifier123:example.org '
      'media mxc://example.org/mediaId12345 reporter@example.org',
    );

    expect(redacted, isNot(contains('@alice:example.org')));
    expect(redacted, isNot(contains('@sender:example.org')));
    expect(redacted, isNot(contains('!abcdef123456:example.org')));
    expect(redacted, isNot(contains('!roomidentifier123:example.org')));
    expect(redacted, isNot(contains('#ops:example.org')));
    expect(redacted, isNot(contains(r'$eventidentifier123:example.org')));
    expect(redacted, isNot(contains('mxc://example.org/mediaId12345')));
    expect(redacted, contains('[MATRIX_USER_ID]'));
    expect(redacted, contains('[MATRIX_ROOM_ID]'));
    expect(redacted, contains('[MATRIX_ROOM_ALIAS]'));
    expect(redacted, contains('[MATRIX_EVENT_ID]'));
    expect(redacted, contains('[MXC_URI]'));
    expect(redacted, contains('reporter@example.org'));
  });

  test('redacts Matrix identifiers embedded in cache filenames', () {
    final redacted = LogRedactor.redact(
      r'Getting cached avatar image for id: shortcutAvatar_@alice:example.org_circle.png '
      r'roomCache_!abcdef123456:example.org_icon.jpg '
      r'eventCache_$eventidentifier123:example.org_icon.bin',
    );

    expect(redacted, isNot(contains('@alice:example.org')));
    expect(redacted, isNot(contains('!abcdef123456:example.org')));
    expect(redacted, isNot(contains(r'$eventidentifier123:example.org')));
    expect(
      redacted,
      contains('shortcutAvatar_[MATRIX_USER_ID]_circle.png'),
    );
    expect(redacted, contains('roomCache_[MATRIX_ROOM_ID]_icon.jpg'));
    expect(redacted, contains('eventCache_[MATRIX_EVENT_ID]_icon.bin'));
  });

  test('redacts room display names from timeline lifecycle logs', () {
    final redacted = LogRedactor.redact(
      'Initializing room timeline for: Private Planning Room thread-a\n'
      'Disposing room timeline for: Secret Test History',
    );

    expect(redacted, isNot(contains('Private Planning Room')));
    expect(redacted, isNot(contains('Secret Test History')));
    expect(redacted, contains('Initializing room timeline for: [ROOM_NAME]'));
    expect(redacted, contains('Disposing room timeline for: [ROOM_NAME]'));
  });

  test('redacts identifying device diagnostics fields', () {
    final redacted = LogRedactor.redact(
      'Device: {computerName: DEV-PC, userName: localuser, '
      'digitalProductId: [1, 2, 3], productId: PROD-123, '
      'registeredOwner: owner@example.com, installDate: 2024-01-01, '
      'deviceId: {DEVICE-GUID}, productName: Windows 11 Pro}',
    );

    expect(redacted, isNot(contains('DEV-PC')));
    expect(redacted, isNot(contains('localuser')));
    expect(redacted, isNot(contains('PROD-123')));
    expect(redacted, isNot(contains('owner@example.com')));
    expect(redacted, isNot(contains('DEVICE-GUID')));
    expect(redacted, contains('productName: Windows 11 Pro'));
    expect(redacted, contains('[REDACTED]'));
  });

  test('redacts LiveKit participant identities in bug report logs', () {
    final redacted = LogRedactor.redactForBugReport(
      'LiveKit local track unpublished: sid=TR_AUDIO '
      'source=TrackSource.screenShareAudio '
      'participant=@alice:example.org:DEVICEID '
      '{"participantIdentity":"@bob:example.org:DEVICEID"}',
    );

    expect(redacted, isNot(contains('@alice:example.org')));
    expect(redacted, isNot(contains('@bob:example.org')));
    expect(redacted, isNot(contains('DEVICEID')));
    expect(redacted, contains('participant=[LIVEKIT_PARTICIPANT]'));
    expect(redacted, contains('"participantIdentity":"[LIVEKIT_PARTICIPANT]"'));
  });

  test('redacts Matrix identifiers with homeserver ports', () {
    final redacted = LogRedactor.redact(
      r'user @alice:example.org:8448 room !abcdef123456:example.org:8448 '
      r'alias #ops:example.org:8448 event $eventidentifier123:example.org:8448 '
      'media mxc://example.org:8448/mediaId12345',
    );

    expect(redacted, isNot(contains('@alice:example.org:8448')));
    expect(redacted, isNot(contains('!abcdef123456:example.org:8448')));
    expect(redacted, isNot(contains('#ops:example.org:8448')));
    expect(
      redacted,
      isNot(contains(r'$eventidentifier123:example.org:8448')),
    );
    expect(redacted, isNot(contains('mxc://example.org:8448/mediaId12345')));
    expect(redacted, contains('[MATRIX_USER_ID]'));
    expect(redacted, contains('[MATRIX_ROOM_ID]'));
    expect(redacted, contains('[MATRIX_ROOM_ALIAS]'));
    expect(redacted, contains('[MATRIX_EVENT_ID]'));
    expect(redacted, contains('[MXC_URI]'));
  });

  test('redacts domainless Matrix SDK identifiers', () {
    final redacted = LogRedactor.redact(
      r'Ignoring call event for room !OLb_cZea4QrRp6s92MfL8qHuozJkKBlU8OH... '
      r'and event $eventidentifierwithoutserver123 while assertion '
      "'!_debugDoingThisLayout' remains readable.",
    );

    expect(redacted, isNot(contains('!OLb_cZea4QrRp6s92MfL8qHuozJkKBlU8OH')));
    expect(redacted, isNot(contains(r'$eventidentifierwithoutserver123')));
    expect(redacted, contains('[MATRIX_ROOM_ID]'));
    expect(redacted, contains('[MATRIX_EVENT_ID]'));
    expect(redacted, contains('!_debugDoingThisLayout'));
  });

  test('redacts Matrix API URIs from exception details', () {
    final redacted = LogRedactor.redactForBugReport(
      'ClientException: Bad request, '
      'uri=https://matrix.example/_matrix/client/v3/rooms/'
      '!roomPathSegmentWithoutServer12345/typing/%40alice%3Aexample.org',
    );

    expect(redacted, contains('[MATRIX_API_URI]'));
    expect(redacted, isNot(contains('/_matrix/client/v3/rooms')));
    expect(redacted, isNot(contains('!roomPathSegmentWithoutServer12345')));
    expect(redacted, isNot(contains('%40alice%3Aexample.org')));
  });

  test('redacts Matrix sync URI query values from exception details', () {
    final redacted = LogRedactor.redactForBugReport(
      'ClientException: sync failed, '
      'uri=https://matrix.example/_matrix/client/v3/sync'
      '?filter=privateFilter&since=s987654321&timeout=30000\\n\\nStack trace',
    );

    expect(redacted, contains('[MATRIX_API_URI]'));
    expect(redacted, contains(r'\n\nStack trace'));
    expect(redacted, isNot(contains('/_matrix/client/v3/sync')));
    expect(redacted, isNot(contains('privateFilter')));
    expect(redacted, isNot(contains('s987654321')));
    expect(redacted, isNot(contains('timeout=30000')));
  });

  test('redacts URL-encoded Matrix identifiers outside API URIs', () {
    final redacted = LogRedactor.redact(
      'path=%40alice%3Aexample.org event=%24eventIdentifier123%3Aexample.org',
    );

    expect(redacted, contains('[MATRIX_IDENTIFIER]'));
    expect(redacted, isNot(contains('%40alice%3Aexample.org')));
    expect(redacted, isNot(contains('%24eventIdentifier123%3Aexample.org')));
  });

  test('redacts Matrix E2EE payload fields', () {
    final redacted = LogRedactor.redact(
      '{"session_id":"SESSION",'
      '"sender_key":"SENDER",'
      '"sender_claimed_ed25519_key":"CLAIMED",'
      '"ciphertext":"CIPHERTEXT"} '
      'device_key=DEVICE forwarding_curve25519_key_chain=CHAIN',
    );

    expect(redacted, isNot(contains('SESSION')));
    expect(redacted, isNot(contains('SENDER')));
    expect(redacted, isNot(contains('CLAIMED')));
    expect(redacted, isNot(contains('CIPHERTEXT')));
    expect(redacted, isNot(contains('DEVICE')));
    expect(redacted, isNot(contains('CHAIN')));
    expect(redacted, contains('[REDACTED]'));
  });

  test('redacts account recovery codes, reset tokens, and TOTP material', () {
    final redacted = LogRedactor.redactForBugReport(
      'Generated IG-7K2P-M9QD-R4VA and recovery_code=IG-2222-3333-4444 '
      '{"recovery_codes":["IG-ABCD-EFGH-JKMP"],'
      '"reset_session_token":"reset-session-secret",'
      '"setup_session_token":"totp-setup-session",'
      '"totp_setup_session_token":"totp-prefixed-session",'
      '"otpauth_uri":"otpauth://totp/Inter%20Galactic:alice?secret=URISECRET",'
      '"manual_secret":"manual-secret",'
      '"totp_secret":"totp-secret","otp":"123456"} '
      'otpauth://totp/Inter%20Galactic:alice?secret=RAWSECRET '
      'manual_secret=assigned-secret setup_session_token=assigned-session '
      'https://ourgalaxy.space/reset?reset_token=query-secret&secret=query-otp-secret',
    );

    expect(redacted, isNot(contains('IG-7K2P-M9QD-R4VA')));
    expect(redacted, isNot(contains('IG-2222-3333-4444')));
    expect(redacted, isNot(contains('IG-ABCD-EFGH-JKMP')));
    expect(redacted, isNot(contains('reset-session-secret')));
    expect(redacted, isNot(contains('totp-setup-session')));
    expect(redacted, isNot(contains('totp-prefixed-session')));
    expect(redacted, isNot(contains('URISECRET')));
    expect(redacted, isNot(contains('manual-secret')));
    expect(redacted, isNot(contains('RAWSECRET')));
    expect(redacted, isNot(contains('assigned-secret')));
    expect(redacted, isNot(contains('assigned-session')));
    expect(redacted, isNot(contains('totp-secret')));
    expect(redacted, isNot(contains('123456')));
    expect(redacted, isNot(contains('query-secret')));
    expect(redacted, isNot(contains('query-otp-secret')));
    expect(redacted, contains('[REDACTED]'));
  });

  test('redacts Matrix room-key bundle fields', () {
    final redacted = LogRedactor.redact(
      '{"type":"io.element.msc4268.room_key_bundle",'
      '"room_key_bundle":"BUNDLE",'
      '"file":{"url":"mxc://example.org/bundleMedia",'
      '"iv":"BUNDLE_IV",'
      '"key":{"k":"BUNDLE_FILE_KEY"},'
      '"hashes":{"sha256":"BUNDLE_HASH"}}} '
      'requesting_device_id=DEVICE123 bundle_url=mxc://example.org/other',
    );

    expect(redacted, isNot(contains('BUNDLE')));
    expect(redacted, isNot(contains('BUNDLE_IV')));
    expect(redacted, isNot(contains('BUNDLE_FILE_KEY')));
    expect(redacted, isNot(contains('BUNDLE_HASH')));
    expect(redacted, isNot(contains('DEVICE123')));
    expect(redacted, isNot(contains('mxc://example.org/bundleMedia')));
    expect(redacted, contains('[MXC_URI]'));
    expect(redacted, contains('[REDACTED]'));
  });

  test('parses diagnostic startup flags', () {
    final options = RuntimeDiagnosticsOptions.fromArgs(
      const ['--ig-debug-logs', '--ig-webrtc-stats'],
    );

    expect(options.debugLogs, isTrue);
    expect(options.webrtcStats, isTrue);
  });
}

const _windowsFixtureDrive = 'C:';

String get _windowsFixtureRoot =>
    '$_windowsFixtureDrive${r'\redaction-fixtures'}';
