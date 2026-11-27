import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';

class AccountRecoveryApiClient {
  AccountRecoveryApiClient({
    http.Client? httpClient,
    Uri? endpoint,
    Duration timeout = const Duration(seconds: 15),
    AccountRecoveryAuthProofProvider? authProofProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _endpoint = endpoint ?? defaultEndpoint,
        _timeout = timeout,
        _authProofProvider = authProofProvider ?? _requestOpenIdProof;

  static final Uri defaultEndpoint = Uri.parse(
    BuildConfig.INTERGALACTIC_ACCOUNT_RECOVERY_ENDPOINT.trim().isEmpty
        ? 'https://ourgalaxy.space/api/intergalactic/account-recovery'
        : BuildConfig.INTERGALACTIC_ACCOUNT_RECOVERY_ENDPOINT,
  );

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Uri _endpoint;
  final Duration _timeout;
  final AccountRecoveryAuthProofProvider _authProofProvider;

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<AccountRecoveryStatus> getStatus({
    required MatrixClient client,
  }) async {
    return getStatusWithProof(await _authProofProvider(client));
  }

  Future<AccountRecoveryStatus> getStatusWithProof(
    AccountRecoveryAuthProof proof,
  ) async {
    final body = await _get('/status', headers: _authHeaders(proof));
    return AccountRecoveryStatus.fromJson(body);
  }

  Future<AccountRecoveryCodesResult> generateRecoveryCodes({
    required MatrixClient client,
  }) async {
    return generateRecoveryCodesWithProof(await _authProofProvider(client));
  }

  Future<AccountRecoveryCodesResult> generateRecoveryCodesWithProof(
    AccountRecoveryAuthProof proof,
  ) async {
    final body = await _post(
      '/recovery-codes/generate',
      headers: _authHeaders(proof),
    );
    return AccountRecoveryCodesResult.fromJson(body);
  }

  Future<AccountRecoveryCodesResult> regenerateRecoveryCodes({
    required MatrixClient client,
  }) async {
    return regenerateRecoveryCodesWithProof(await _authProofProvider(client));
  }

  Future<AccountRecoveryCodesResult> regenerateRecoveryCodesWithProof(
    AccountRecoveryAuthProof proof,
  ) async {
    final body = await _post(
      '/recovery-codes/regenerate',
      headers: _authHeaders(proof),
    );
    return AccountRecoveryCodesResult.fromJson(body);
  }

  Future<AccountRecoveryResetStartResult> startReset({
    required String username,
  }) async {
    final body = await _post(
      '/reset/start',
      body: {'username': username.trim()},
    );
    return AccountRecoveryResetStartResult.fromJson(body);
  }

  Future<AccountRecoveryResetVerifyResult> verifyReset({
    required String username,
    required String recoveryCode,
  }) async {
    final body = await _post(
      '/reset/verify',
      body: {
        'username': username.trim(),
        'factor': 'recovery_code',
        'recovery_code': recoveryCode.trim(),
      },
    );
    return _resetVerifyResult(body);
  }

  Future<AccountRecoveryResetVerifyResult> verifyResetWithTotp({
    required String username,
    required String otp,
  }) async {
    final body = await _post(
      '/reset/verify',
      body: {
        'username': username.trim(),
        'factor': 'totp',
        'otp': otp.trim(),
      },
    );
    return _resetVerifyResult(body);
  }

  Future<AccountRecoveryResetCompleteResult> completeReset({
    required String resetSessionToken,
    required String newPassword,
  }) async {
    final body = await _post(
      '/reset/complete',
      body: {
        'reset_session_token': resetSessionToken,
        'new_password': newPassword,
      },
    );
    return AccountRecoveryResetCompleteResult.fromJson(body);
  }

  Future<AccountRecoveryTotpSetupStartResult> startTotp({
    required MatrixClient client,
  }) async {
    return startTotpWithProof(await _authProofProvider(client));
  }

  Future<AccountRecoveryTotpSetupStartResult> startTotpWithProof(
    AccountRecoveryAuthProof proof,
  ) async {
    try {
      final body = await _post('/totp/start', headers: _authHeaders(proof));
      return AccountRecoveryTotpSetupStartResult.fromJson(body);
    } on AccountRecoveryApiException catch (error) {
      if (error.isTotpUnavailable) {
        return const AccountRecoveryTotpSetupStartResult.unavailable();
      }
      rethrow;
    }
  }

  Future<AccountRecoveryTotpMutationResult> verifyTotp({
    required MatrixClient client,
    required String setupSessionToken,
    required String otp,
  }) async {
    final proof = await _authProofProvider(client);
    return verifyTotpWithProof(
      proof,
      setupSessionToken: setupSessionToken,
      otp: otp,
    );
  }

  Future<AccountRecoveryTotpMutationResult> verifyTotpWithProof(
    AccountRecoveryAuthProof proof, {
    required String setupSessionToken,
    required String otp,
  }) async {
    try {
      final body = await _post(
        '/totp/verify',
        headers: _authHeaders(proof),
        body: {
          'setup_session_token': setupSessionToken.trim(),
          'otp': otp.trim(),
        },
      );
      return AccountRecoveryTotpMutationResult.fromJson(body);
    } on AccountRecoveryApiException catch (error) {
      if (error.isTotpUnavailable) {
        return const AccountRecoveryTotpMutationResult.unavailable();
      }
      rethrow;
    }
  }

  Future<AccountRecoveryTotpMutationResult> disableTotp({
    required MatrixClient client,
    required String otp,
  }) async {
    final proof = await _authProofProvider(client);
    return disableTotpWithProof(proof, otp: otp);
  }

  Future<AccountRecoveryTotpMutationResult> disableTotpWithProof(
    AccountRecoveryAuthProof proof, {
    required String otp,
  }) async {
    try {
      final body = await _post(
        '/totp/disable',
        headers: _authHeaders(proof),
        body: {'otp': otp.trim()},
      );
      return AccountRecoveryTotpMutationResult.fromJson(body);
    } on AccountRecoveryApiException catch (error) {
      if (error.isTotpUnavailable) {
        return const AccountRecoveryTotpMutationResult.unavailable();
      }
      rethrow;
    }
  }

  AccountRecoveryResetVerifyResult _resetVerifyResult(
    Map<String, dynamic> body,
  ) {
    final result = AccountRecoveryResetVerifyResult.fromJson(body);
    if (!result.verified) {
      final errorMap = _map(body['error']);
      final code = errorMap['code']?.toString() ?? 'invalid_recovery_factor';
      final message =
          errorMap['message']?.toString() ?? 'Recovery verification failed.';
      Log.w(
        'Account recovery reset verify rejected status=200 code=$code',
        category: LogCategory.app,
        source: 'account-recovery',
      );
      throw AccountRecoveryApiException(
        statusCode: 200,
        code: code,
        message: message,
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _httpClient.get(
      _uri(path),
      headers: {
        ...headers,
        'Accept': 'application/json',
      },
    ).timeout(_timeout);
    return _decodeResponse(response, path: path);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) async {
    final response = await _httpClient
        .post(
          _uri(path),
          headers: {
            ...headers,
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout);
    return _decodeResponse(response, path: path);
  }

  Uri _uri(String path) {
    final basePath = _endpoint.path.endsWith('/')
        ? _endpoint.path.substring(0, _endpoint.path.length - 1)
        : _endpoint.path;
    return _endpoint.replace(path: '$basePath$path');
  }

  Map<String, String> _authHeaders(AccountRecoveryAuthProof proof) {
    return {
      'Authorization': 'Bearer ${proof.accessToken}',
      'X-Matrix-Server-Name': proof.matrixServerName,
    };
  }

  Map<String, dynamic> _decodeResponse(
    http.Response response, {
    required String path,
  }) {
    final body = response.body.trim();
    Object? decoded;

    if (body.isEmpty) {
      decoded = <String, dynamic>{};
    } else {
      try {
        decoded = jsonDecode(body);
      } catch (_) {
        decoded = <String, dynamic>{};
      }
    }

    final json = decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = json['error'];
      final errorMap = error is Map
          ? error.map((key, value) => MapEntry(key.toString(), value))
          : const <String, dynamic>{};
      final code = errorMap['code']?.toString() ?? 'request_failed';
      if (!(path.startsWith('/totp/') && code == 'totp_not_enabled')) {
        Log.w(
          'Account recovery request failed path=$path '
          'status=${response.statusCode} code=$code',
          category: LogCategory.app,
          source: 'account-recovery',
        );
      }
      throw AccountRecoveryApiException(
        statusCode: response.statusCode,
        code: code,
        message: errorMap['message']?.toString() ??
            'Account recovery request failed.',
      );
    }

    return json;
  }

  static Future<AccountRecoveryAuthProof> _requestOpenIdProof(
    MatrixClient client,
  ) async {
    final matrixClient = client.getMatrixClient();
    final userId = matrixClient.userID;
    if (userId == null || userId.trim().isEmpty) {
      throw const AccountRecoveryApiException(
        statusCode: 0,
        code: 'missing_matrix_user',
        message: 'This Matrix session does not have a user ID yet.',
      );
    }

    final token = await matrixClient.requestOpenIdToken(userId, {});
    return AccountRecoveryAuthProof(
      accessToken: token.accessToken,
      matrixServerName: token.matrixServerName,
    );
  }
}

typedef AccountRecoveryAuthProofProvider = Future<AccountRecoveryAuthProof>
    Function(MatrixClient client);

class AccountRecoveryAuthProof {
  const AccountRecoveryAuthProof({
    required this.accessToken,
    required this.matrixServerName,
  });

  final String accessToken;
  final String matrixServerName;
}

class AccountRecoveryStatus {
  const AccountRecoveryStatus({
    required this.enabled,
    required this.userId,
    required this.homeserver,
    required this.recoveryCodes,
    required this.totp,
    required this.resetSessionTtl,
  });

  final bool enabled;
  final String? userId;
  final String? homeserver;
  final AccountRecoveryCodesStatus recoveryCodes;
  final AccountRecoveryTotpStatus totp;
  final Duration resetSessionTtl;

  factory AccountRecoveryStatus.fromJson(Map<String, dynamic> json) {
    return AccountRecoveryStatus(
      enabled: json['enabled'] == true,
      userId: json['user_id']?.toString(),
      homeserver: json['homeserver']?.toString(),
      recoveryCodes: AccountRecoveryCodesStatus.fromJson(
        _map(json['recovery_codes']),
      ),
      totp: AccountRecoveryTotpStatus.fromJson(_map(json['totp'])),
      resetSessionTtl: Duration(
        milliseconds: _intValue(_map(json['reset'])['session_ttl_ms']),
      ),
    );
  }
}

class AccountRecoveryCodesStatus {
  const AccountRecoveryCodesStatus({
    required this.enrolled,
    required this.activeCount,
    this.generatedAt,
  });

  final bool enrolled;
  final int activeCount;
  final DateTime? generatedAt;

  factory AccountRecoveryCodesStatus.fromJson(Map<String, dynamic> json) {
    return AccountRecoveryCodesStatus(
      enrolled: json['enrolled'] == true,
      activeCount: _intValue(json['active_count']),
      generatedAt: _dateTime(json['generated_at']),
    );
  }
}

class AccountRecoveryTotpStatus {
  const AccountRecoveryTotpStatus({
    required this.available,
    required this.enabled,
  });

  final bool available;
  final bool enabled;

  factory AccountRecoveryTotpStatus.fromJson(Map<String, dynamic> json) {
    return AccountRecoveryTotpStatus(
      available: json['available'] == true,
      enabled: json['enabled'] == true,
    );
  }
}

class AccountRecoveryCodesResult {
  const AccountRecoveryCodesResult({
    required this.codes,
    required this.displayOnce,
    this.generatedAt,
  });

  final List<String> codes;
  final bool displayOnce;
  final DateTime? generatedAt;

  factory AccountRecoveryCodesResult.fromJson(Map<String, dynamic> json) {
    final rawCodes = json['recovery_codes'];
    return AccountRecoveryCodesResult(
      codes: rawCodes is List
          ? rawCodes.map((entry) => entry.toString()).toList(growable: false)
          : const [],
      displayOnce: json['display_once'] != false,
      generatedAt: _dateTime(json['generated_at']),
    );
  }
}

class AccountRecoveryResetStartResult {
  const AccountRecoveryResetStartResult({required this.accepted});

  final bool accepted;

  factory AccountRecoveryResetStartResult.fromJson(Map<String, dynamic> json) {
    return AccountRecoveryResetStartResult(accepted: json['accepted'] == true);
  }
}

class AccountRecoveryResetVerifyResult {
  const AccountRecoveryResetVerifyResult({
    required this.verified,
    required this.resetSessionToken,
    this.expiresAt,
  });

  final bool verified;
  final String resetSessionToken;
  final DateTime? expiresAt;

  factory AccountRecoveryResetVerifyResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final token = json['reset_session_token']?.toString() ?? '';
    return AccountRecoveryResetVerifyResult(
      verified: json['verified'] == true && token.isNotEmpty,
      resetSessionToken: token,
      expiresAt: _dateTime(json['expires_at']),
    );
  }
}

class AccountRecoveryResetCompleteResult {
  const AccountRecoveryResetCompleteResult({required this.ok});

  final bool ok;

  factory AccountRecoveryResetCompleteResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return AccountRecoveryResetCompleteResult(ok: json['ok'] == true);
  }
}

class AccountRecoveryTotpSetupStartResult {
  const AccountRecoveryTotpSetupStartResult({
    required this.available,
    required this.setupSessionToken,
    required this.otpauthUri,
    required this.manualSecret,
    required this.digits,
    required this.period,
    this.expiresAt,
  });

  const AccountRecoveryTotpSetupStartResult.unavailable()
      : available = false,
        setupSessionToken = '',
        otpauthUri = '',
        manualSecret = '',
        digits = 6,
        period = const Duration(seconds: 30),
        expiresAt = null;

  final bool available;
  final String setupSessionToken;
  final String otpauthUri;
  final String manualSecret;
  final int digits;
  final Duration period;
  final DateTime? expiresAt;

  bool get hasSetupMaterial =>
      available &&
      setupSessionToken.isNotEmpty &&
      otpauthUri.isNotEmpty &&
      manualSecret.isNotEmpty;

  factory AccountRecoveryTotpSetupStartResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return AccountRecoveryTotpSetupStartResult(
      available: json['available'] != false,
      setupSessionToken: json['setup_session_token']?.toString() ?? '',
      otpauthUri: json['otpauth_uri']?.toString() ?? '',
      manualSecret: json['manual_secret']?.toString() ?? '',
      digits: _intValue(json['digits'], fallback: 6),
      period: Duration(seconds: _intValue(json['period'], fallback: 30)),
      expiresAt: _dateTime(json['expires_at']),
    );
  }
}

class AccountRecoveryTotpMutationResult {
  const AccountRecoveryTotpMutationResult({
    required this.available,
    required this.ok,
    required this.enabled,
  });

  const AccountRecoveryTotpMutationResult.unavailable()
      : available = false,
        ok = false,
        enabled = false;

  final bool available;
  final bool ok;
  final bool enabled;

  factory AccountRecoveryTotpMutationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final enabled = json['enabled'] == true;
    return AccountRecoveryTotpMutationResult(
      available: json['available'] != false,
      ok: json['ok'] == true || enabled || json['enabled'] == false,
      enabled: enabled,
    );
  }
}

class AccountRecoveryApiException implements Exception {
  const AccountRecoveryApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'AccountRecoveryApiException($statusCode, $code)';

  bool get isTotpUnavailable => code == 'totp_not_enabled' || statusCode == 501;
}

class AccountRecoveryEligibility {
  static const String localServerName = 'ourgalaxy.space';

  static Set<String> get allowedHomeservers =>
      BuildConfig.INTERGALACTIC_ACCOUNT_RECOVERY_ALLOWED_HOMESERVERS
          .split(',')
          .map((entry) => _normalizeHomeserver(entry))
          .where((entry) => entry.isNotEmpty)
          .toSet();

  static bool isAllowedHomeserverInput(String input) {
    return allowedHomeservers.contains(_normalizeHomeserver(input));
  }

  static bool isAllowedHomeserverUri(Uri? uri) {
    if (uri == null) {
      return false;
    }
    return isAllowedHomeserverInput(
        uri.host.isEmpty ? uri.toString() : uri.host);
  }

  static bool isLocalMatrixUserId(String? userId) {
    return userId?.trim().toLowerCase().endsWith(':$localServerName') == true;
  }

  static bool isLocalMatrixClient(MatrixClient client) {
    final matrixClient = client.getMatrixClient();
    return isLocalMatrixUserId(matrixClient.userID) &&
        (isAllowedHomeserverUri(matrixClient.homeserver) ||
            isAllowedHomeserverUri(matrixClient.baseUri));
  }

  static String promptPreferenceKey(MatrixClient client) {
    final userId = client.getMatrixClient().userID;
    if (userId == null || userId.isEmpty) {
      return client.identifier;
    }
    return userId.toLowerCase();
  }

  static String recoveryDisplayName(String homeserverInput) {
    final normalized = _normalizeHomeserver(homeserverInput);
    return normalized.isEmpty ? homeserverInput.trim() : normalized;
  }

  static String _normalizeHomeserver(String input) {
    var value = input.trim().toLowerCase();
    if (value.isEmpty) {
      return '';
    }

    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.host.isNotEmpty) {
      value = parsed.host.toLowerCase();
    }

    value = value
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first
        .toLowerCase();
    return value;
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return {};
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime? _dateTime(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}
