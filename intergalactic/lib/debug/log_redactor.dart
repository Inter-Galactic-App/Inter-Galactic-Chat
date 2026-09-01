class LogRedactor {
  static const _replacement = '[REDACTED]';
  static const _pathReplacement = '[LOCAL_PATH]';
  static const _matrixApiUriReplacement = '[MATRIX_API_URI]';
  static const _privateIpReplacement = '[PRIVATE_IP]';

  static final RegExp _authorizationHeader = RegExp(
    r'''((?:"|')?(?:proxy[_-]?)?authorization(?:"|')?\s*[:=]\s*(?:"|')?)([A-Za-z]+\s+)?([^"'\s,;}\]]+)''',
    caseSensitive: false,
  );

  static final RegExp _querySecret = RegExp(
    r'''([?&](?:access_token|refresh_token|token|jwt|password|recovery_code|recovery_codes|reset_token|reset_session_token|setup_session_token|totp_setup_session_token|totp_secret|totp_code|otpauth_uri|manual_secret|otp|secret|pushkey|push_key|push_token|fcm_token|firebase_token|apns_token|device_token)=)[^&\s"')\]\[{}<>,;]+''',
    caseSensitive: false,
  );

  static final RegExp _signedUrlQuerySecret = RegExp(
    r'''([?&](?:x[-_]?signature|x[-_]?expires|signature|sig|expires|_nc_[a-z0-9_]+|edm|ccb|stp|idc|shp|shcp|oh|oe)=)[^&\s"')\]\[{}<>,;]+''',
    caseSensitive: false,
  );

  static final RegExp _matrixApiUri = RegExp(
    r'''https?://[^\s"'<>\\)\]\},;]+/_matrix/[^\s"'<>\\)\]\},;]+''',
    caseSensitive: false,
  );

  static final RegExp _iceCandidate = RegExp(
    r'(?:a=)?candidate:[^\\"\r\n]*',
    caseSensitive: false,
  );

  static final RegExp _iceCandidateType = RegExp(
    r'\btyp\s+([a-z0-9]+)\b',
    caseSensitive: false,
  );

  static final RegExp _iceCandidateTransport = RegExp(
    r'\bcandidate:[^\s]+\s+\d+\s+([a-z0-9]+)\s+',
    caseSensitive: false,
  );

  static final RegExp _iceSdpCredential = RegExp(
    r'\ba=ice-(ufrag|pwd):[^\\"\r\n]*',
    caseSensitive: false,
  );

  static final RegExp _iceCredentialJson = RegExp(
    r'''(["'](?:ice[_-]?(?:ufrag|pwd)|username[_-]?fragment)["']\s*:\s*["'])([^"']+)(["'])''',
    caseSensitive: false,
  );

  static final RegExp _iceCredentialAssignment = RegExp(
    r'''\b((?:ice[_-]?(?:ufrag|pwd)|username[_-]?fragment)\s*[:=]\s*)([^\\\s"',;}\]]+)''',
    caseSensitive: false,
  );

  static final RegExp _jsonSecret = RegExp(
    r'''(["'](?:access[_-]?token|refresh[_-]?token|matrix[_-]?access[_-]?token|openid[_-]?token|id[_-]?token|livekit[_-]?jwt|jwt|(?:proxy[_-]?)?authorization|auth[_-]?token|password|passwd|cookie|session[_-]?id|session[_-]?key|session[_-]?keys|reset[_-]?(?:token|session[_-]?token)|setup[_-]?session[_-]?token|totp[_-]?setup[_-]?session[_-]?token|recovery[_-]?code|recovery[_-]?codes|totp[_-]?(?:secret|code)|otpauth[_-]?uri|manual[_-]?secret|otp|one[_-]?time[_-]?password|authenticator[_-]?code|crypto[_-]?secret|megolm[_-]?session|olm[_-]?account|ciphertext|sender[_-]?key|sender[_-]?claimed[_-]?ed25519[_-]?key|forwarding[_-]?curve25519[_-]?key[_-]?chain|device[_-]?key|device[_-]?keys|device[_-]?token|requesting[_-]?device[_-]?id|room[_-]?key[_-]?bundle|bundle[_-]?url|file[_-]?url|mxc[_-]?(?:uri|url)|iv|sha256|k|push[_-]?key|pushkey|push[_-]?token|fcm[_-]?token|firebase[_-]?token|apns[_-]?token|private[_-]?key|recovery[_-]?key|backup[_-]?key|client[_-]?secret|api[_-]?key|secret)["']\s*:\s*["'])([^"']+)(["'])''',
    caseSensitive: false,
  );

  static final RegExp _assignmentSecret = RegExp(
    r'\b(access[_-]?token|refresh[_-]?token|matrix[_-]?access[_-]?token|openid[_-]?token|id[_-]?token|livekit[_-]?jwt|jwt|(?:proxy[_-]?)?authorization|auth[_-]?token|password|passwd|cookie|session[_-]?id|session[_-]?key|session[_-]?keys|reset[_-]?(?:token|session[_-]?token)|setup[_-]?session[_-]?token|totp[_-]?setup[_-]?session[_-]?token|recovery[_-]?code|recovery[_-]?codes|totp[_-]?(?:secret|code)|otpauth[_-]?uri|manual[_-]?secret|otp|one[_-]?time[_-]?password|authenticator[_-]?code|crypto[_-]?secret|megolm[_-]?session|olm[_-]?account|ciphertext|sender[_-]?key|sender[_-]?claimed[_-]?ed25519[_-]?key|forwarding[_-]?curve25519[_-]?key[_-]?chain|device[_-]?key|device[_-]?keys|device[_-]?token|requesting[_-]?device[_-]?id|room[_-]?key[_-]?bundle|bundle[_-]?url|file[_-]?url|mxc[_-]?(?:uri|url)|iv|sha256|k|push[_-]?key|pushkey|push[_-]?token|fcm[_-]?token|firebase[_-]?token|apns[_-]?token|private[_-]?key|recovery[_-]?key|backup[_-]?key|client[_-]?secret|api[_-]?key|secret)\s*=\s*([^\s,;}\]]+)',
    caseSensitive: false,
  );

  static final RegExp _matrixSdkRoomKeySession = RegExp(
    r'\b((?:Received\s+)?room\s+key\s+with\s+session\s+)([A-Za-z0-9._=\/+\-]{6,})',
    caseSensitive: false,
  );

  static final RegExp _matrixRequestingDeviceAssignment = RegExp(
    r'\b(requesting[_-]?device\s*=\s*)([^\s,;}\]]+)',
    caseSensitive: false,
  );

  static final RegExp _shortDiagnosticHash = RegExp(r'^[a-f0-9]{12}$');

  static final RegExp _cookieHeader = RegExp(
    r'((?:cookie|set-cookie)\s*[:=]\s*)([^\r\n}\]]+)',
    caseSensitive: false,
  );

  static final RegExp _matrixAccessToken = RegExp(
    r'\b(?:syt|syd|sya)_[A-Za-z0-9_\-./=]+\b',
  );

  static final RegExp _jwt = RegExp(
    r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
  );

  static final RegExp _fcmPushToken = RegExp(
    r'\b[A-Za-z0-9_-]{10,}:[A-Za-z0-9_-]{60,}\b',
  );

  static final RegExp _pushSecretLabelled = RegExp(
    r'\b((?:current\s+push\s+key|push\s*key|pushkey|push[_-]?key|push\s*token|push[_-]?token|fcm\s*token|fcm[_-]?token|firebase\s*token|firebase[_-]?token|apns\s*token|apns[_-]?token|device\s*token|device[_-]?token)\s*[:=]\s*)([A-Za-z0-9:_\-./+=]{16,})',
    caseSensitive: false,
  );

  static final RegExp _matrixRecoveryKeyGrouped = RegExp(
    r'\b(?:[A-Za-z0-9]{4}[\s-]){7,}[A-Za-z0-9]{4}\b',
  );

  static final RegExp _matrixRecoveryKeyLabelled = RegExp(
    r'\b((?:matrix\s+)?recovery\s+key\s*(?:is|:|=)\s*)([A-Za-z0-9][A-Za-z0-9\s-]{31,})',
    caseSensitive: false,
  );

  static final RegExp _accountRecoveryCode = RegExp(
    r'\bIG-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}\b',
    caseSensitive: false,
  );

  static final RegExp _otpauthUri = RegExp(
    r'''\botpauth://[^\s"')\]\[{}<>,;]+''',
    caseSensitive: false,
  );

  static final RegExp _matrixUserId = RegExp(
    r'(^|[^A-Za-z0-9.\/+\-])@[A-Za-z0-9._=\/+\-]+:[A-Za-z0-9.-]+(?::\d{1,5})?',
    multiLine: true,
  );

  static final RegExp _matrixRoomId = RegExp(
    r'(^|[^A-Za-z0-9.\/+\-])![A-Za-z0-9._=\/+\-]+:[A-Za-z0-9.-]+(?::\d{1,5})?',
    multiLine: true,
  );

  static final RegExp _matrixBareRoomId = RegExp(
    r'(^|[^A-Za-z0-9.\/+\-])![A-Za-z0-9][A-Za-z0-9._=\/+\-]{10,}(?:\.\.\.)?',
    multiLine: true,
  );

  static final RegExp _matrixDashRoomId = RegExp(
    r'(^|[^A-Za-z0-9.\/+\-])!-[A-Za-z0-9._=\/+\-]{10,}(?:\.\.\.)?',
    multiLine: true,
  );

  static final RegExp _matrixRoomAlias = RegExp(
    r'(^|[^A-Za-z0-9.\/+\-])#[A-Za-z0-9._=\/+\-]+:[A-Za-z0-9.-]+(?::\d{1,5})?',
    multiLine: true,
  );

  static final RegExp _matrixEventId = RegExp(
    r'(^|[^A-Za-z0-9.\/+\-])\$[A-Za-z0-9._=\/+\-]{8,}(?::[A-Za-z0-9.-]+(?::\d{1,5})?)?',
    multiLine: true,
  );

  static final RegExp _matrixBareEventId = RegExp(
    r'(^|[^A-Za-z0-9.\/+\-])\$[A-Za-z0-9][A-Za-z0-9._=\/+\-]{10,}(?:\.\.\.)?',
    multiLine: true,
  );

  static final RegExp _mxcUri = RegExp(
    r'\bmxc://[A-Za-z0-9.-]+(?::\d{1,5})?/[A-Za-z0-9._=\/+\-]+',
    caseSensitive: false,
  );

  static final RegExp _urlEncodedMatrixIdentifier = RegExp(
    r'%(?:40|21|23|24)[A-Za-z0-9._%+\-=]{6,}(?:%3A[A-Za-z0-9._%+\-=:-]+)?',
    caseSensitive: false,
  );

  static final RegExp _windowsLocalPath = RegExp(
    r'\b[A-Za-z]:\\[^\s\r\n"<>|]+',
  );

  static final RegExp _unixLocalPath = RegExp(
    r'(?<![A-Za-z0-9_])/(?:Users|home|var|tmp|private|mnt|Volumes)/[^\s"<>]+',
  );

  static final RegExp _privateIpv4 = RegExp(
    r'(^|[^A-Za-z0-9])((?:10|127)\.(?:\d{1,3}\.){2}\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|169\.254\.\d{1,3}\.\d{1,3})(?::\d{1,5})?',
    multiLine: true,
  );

  static final RegExp _privateIpv6 = RegExp(
    r'(^|[^A-Za-z0-9:])((?:::1)|(?:fe80|fc[0-9a-f]|fd[0-9a-f]):[0-9a-f:.%]+)(?::\d{1,5})?',
    caseSensitive: false,
    multiLine: true,
  );

  static final RegExp _emailAddress = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );

  static final RegExp _liveKitParticipantAssignment = RegExp(
    r'\b((?:participant(?:[_-]?identity)?|participantIdentity)\s*=\s*)([^\s,;}\]]+)',
    caseSensitive: false,
  );

  static final RegExp _liveKitParticipantJson = RegExp(
    r'''(["'](?:participant(?:[_-]?identity)?|participantIdentity)["']\s*:\s*["'])([^"']+)(["'])''',
    caseSensitive: false,
  );

  static final RegExp _timelineRoomNameLog = RegExp(
    r'\b((?:Initializing|Disposing) room timeline for:\s*)([^\r\n\x1B]*)',
    caseSensitive: false,
  );

  static final RegExp _diagnosticDeviceInfoField = RegExp(
    r'\b((?:computer[_-]?name|user[_-]?name|registered[_-]?owner|product[_-]?id|digital[_-]?product[_-]?id|device[_-]?id|machine[_-]?guid|serial[_-]?number|install[_-]?date)\s*[:=]\s*)(\[[^\]\r\n]*\]|\{[^\}\r\n]*\}|[^,;}\]\r\n]+)',
    caseSensitive: false,
  );

  static String redact(
    String input, {
    Iterable<String> dynamicSecrets = const [],
    bool redactLocalPaths = false,
    bool redactEmails = false,
  }) {
    var text = input;

    for (final secret in dynamicSecrets) {
      if (secret.isEmpty) {
        continue;
      }
      text = text.replaceAll(secret, _replacement);
    }

    text = text.replaceAllMapped(
      _authorizationHeader,
      (match) {
        if (_isAlreadyRedactedMatch(match.group(3))) {
          return match.group(0)!;
        }
        return '${match.group(1)}${match.group(2) ?? ''}$_replacement';
      },
    );
    text = text.replaceAllMapped(
      _cookieHeader,
      (match) => '${match.group(1)}$_replacement',
    );
    text = text.replaceAll(_matrixApiUri, _matrixApiUriReplacement);
    text = text.replaceAllMapped(
      _querySecret,
      (match) => '${match.group(1)}$_replacement',
    );
    text = text.replaceAllMapped(
      _signedUrlQuerySecret,
      (match) => '${match.group(1)}$_replacement',
    );
    text = _redactIceDiagnostics(text);
    text = text.replaceAllMapped(
      _jsonSecret,
      (match) => '${match.group(1)}$_replacement${match.group(3)}',
    );
    text = text.replaceAllMapped(
      _assignmentSecret,
      (match) {
        if (_isAlreadyRedactedMatch(match.group(2))) {
          return match.group(0)!;
        }
        return '${match.group(1)}=$_replacement';
      },
    );
    text = text.replaceAllMapped(
      _matrixSdkRoomKeySession,
      (match) => '${match.group(1)}$_replacement',
    );
    text = text.replaceAllMapped(
      _matrixRequestingDeviceAssignment,
      (match) {
        final value = match.group(2)!;
        if (_isAlreadyRedactedMatch(value) ||
            _shortDiagnosticHash.hasMatch(value)) {
          return match.group(0)!;
        }
        return '${match.group(1)}$_replacement';
      },
    );
    text = text.replaceAllMapped(
      _diagnosticDeviceInfoField,
      (match) => '${match.group(1)}$_replacement',
    );
    text = text.replaceAll(_matrixAccessToken, _replacement);
    text = text.replaceAll(_jwt, _replacement);
    text = text.replaceAllMapped(
      _pushSecretLabelled,
      (match) => '${match.group(1)}$_replacement',
    );
    text = text.replaceAll(_fcmPushToken, _replacement);
    text = text.replaceAllMapped(
      _matrixRecoveryKeyLabelled,
      (match) => '${match.group(1)}$_replacement',
    );
    text = text.replaceAll(_accountRecoveryCode, _replacement);
    text = text.replaceAll(_otpauthUri, _replacement);
    text = text.replaceAll(_matrixRecoveryKeyGrouped, _replacement);
    text = _redactLiveKitParticipantIdentities(text);
    text = _redactTimelineRoomNames(text);
    text = _redactMatrixIdentifiers(text);
    text = _redactPrivateIpAddresses(text);

    if (redactLocalPaths) {
      text = text.replaceAllMapped(_windowsLocalPath, _localPathReplacement);
      text = text.replaceAllMapped(_unixLocalPath, _localPathReplacement);
    }

    if (redactEmails) {
      text = text.replaceAll(_emailAddress, _replacement);
    }

    return text;
  }

  static String redactForBugReport(
    String input, {
    Iterable<String> dynamicSecrets = const [],
    bool redactEmails = true,
  }) {
    return redact(
      input,
      dynamicSecrets: dynamicSecrets,
      redactLocalPaths: true,
      redactEmails: redactEmails,
    );
  }

  static String _redactIceDiagnostics(String input) {
    var text = input;
    text = text.replaceAllMapped(
      _iceSdpCredential,
      (match) => 'a=ice-${match.group(1)!.toLowerCase()}:$_replacement',
    );
    text = text.replaceAllMapped(
      _iceCredentialJson,
      (match) => '${match.group(1)}$_replacement${match.group(3)}',
    );
    text = text.replaceAllMapped(
      _iceCredentialAssignment,
      (match) {
        if (_isAlreadyRedactedMatch(match.group(2))) {
          return match.group(0)!;
        }
        return '${match.group(1)}$_replacement';
      },
    );
    text = text.replaceAllMapped(_iceCandidate, _iceCandidateReplacement);
    return text;
  }

  static String _iceCandidateReplacement(Match match) {
    final candidate = match.group(0)!;
    final prefix = candidate.toLowerCase().startsWith('a=candidate:')
        ? 'a=candidate:'
        : 'candidate:';
    final type =
        _iceCandidateType.firstMatch(candidate)?.group(1)?.toLowerCase() ??
            'unknown';
    final transport =
        _iceCandidateTransport.firstMatch(candidate)?.group(1)?.toLowerCase() ??
            'unknown';
    final route = _iceCandidateRouteClass(candidate, type);
    return '$prefix[ICE_CANDIDATE type=$type transport=$transport route=$route]';
  }

  static String _iceCandidateRouteClass(String candidate, String type) {
    if (_containsPrivateIp(candidate)) {
      return 'private';
    }
    if (candidate.toLowerCase().contains('.local')) {
      return 'mdns';
    }
    switch (type) {
      case 'relay':
        return 'relay';
      case 'srflx':
        return 'server-reflexive';
      case 'prflx':
        return 'peer-reflexive';
      case 'host':
        return 'host';
      default:
        return 'unknown';
    }
  }

  static String _redactLiveKitParticipantIdentities(String input) {
    var text = input;
    text = text.replaceAllMapped(
      _liveKitParticipantJson,
      (match) => '${match.group(1)}[LIVEKIT_PARTICIPANT]${match.group(3)}',
    );
    text = text.replaceAllMapped(
      _liveKitParticipantAssignment,
      (match) => '${match.group(1)}[LIVEKIT_PARTICIPANT]',
    );
    return text;
  }

  static String _redactTimelineRoomNames(String input) {
    return input.replaceAllMapped(
      _timelineRoomNameLog,
      (match) => '${match.group(1)}[ROOM_NAME]',
    );
  }

  static String _redactMatrixIdentifiers(String input) {
    var text = input;
    text = text.replaceAll(_mxcUri, '[MXC_URI]');
    text = text.replaceAll(
      _urlEncodedMatrixIdentifier,
      '[MATRIX_IDENTIFIER]',
    );
    text = _replaceSigilIdentifier(text, _matrixUserId, '[MATRIX_USER_ID]');
    text = _replaceSigilIdentifier(text, _matrixRoomId, '[MATRIX_ROOM_ID]');
    text = _replaceSigilIdentifier(text, _matrixBareRoomId, '[MATRIX_ROOM_ID]');
    text = _replaceSigilIdentifier(text, _matrixDashRoomId, '[MATRIX_ROOM_ID]');
    text =
        _replaceSigilIdentifier(text, _matrixRoomAlias, '[MATRIX_ROOM_ALIAS]');
    text = _replaceSigilIdentifier(text, _matrixEventId, '[MATRIX_EVENT_ID]');
    text =
        _replaceSigilIdentifier(text, _matrixBareEventId, '[MATRIX_EVENT_ID]');
    return text;
  }

  static String _replaceSigilIdentifier(
    String input,
    RegExp pattern,
    String replacement,
  ) {
    return input.replaceAllMapped(
      pattern,
      (match) => '${match.group(1) ?? ''}$replacement',
    );
  }

  static String _redactPrivateIpAddresses(String input) {
    var text = input;
    text = text.replaceAllMapped(
      _privateIpv4,
      (match) => '${match.group(1) ?? ''}$_privateIpReplacement',
    );
    text = text.replaceAllMapped(
      _privateIpv6,
      (match) => '${match.group(1) ?? ''}$_privateIpReplacement',
    );
    return text;
  }

  static bool _containsPrivateIp(String input) {
    return _privateIpv4.hasMatch(input) || _privateIpv6.hasMatch(input);
  }

  static String _localPathReplacement(Match match) {
    final path = match.group(0)!;
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    final tail = segments.isEmpty ? '' : '/${segments.last}';
    return '$_pathReplacement$tail';
  }

  static bool _isAlreadyRedactedMatch(String? value) {
    return value == _replacement ||
        value == _replacement.substring(0, _replacement.length - 1);
  }
}
