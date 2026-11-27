import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intergalactic/client/components/soundboard/soundboard_authority_client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_signing.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';

/// Acquires a short-lived Matrix OpenID proof for the current session. Injected
/// so tests supply a canned proof without a live homeserver.
typedef SoundboardAuthorityProofProvider =
    Future<SoundboardAuthorityOpenIdProof> Function(MatrixClient client);

/// Live HTTP implementation of [SoundboardAuthorityClient] against the deployed
/// `soundboard-authority` service.
///
/// The only credential sent is a short-lived Matrix OpenID proof (never a
/// long-lived access token — see the contract "Authentication"), carried in the
/// request body's `auth` field. Endpoint base follows the same
/// `https://ourgalaxy.space/api/intergalactic/<service>` convention as the
/// account-recovery and bug-report services, configurable via BuildConfig.
///
/// `.well-known` federation discovery (for other homeservers) is a future
/// enhancement; this single-homeserver deployment uses the fixed configured
/// base, matching how the other Inter Galactic services resolve their host.
class MatrixSoundboardAuthorityClient implements SoundboardAuthorityClient {
  MatrixSoundboardAuthorityClient({
    required MatrixClient client,
    http.Client? httpClient,
    Uri? endpoint,
    Duration timeout = const Duration(seconds: 15),
    SoundboardAuthorityProofProvider? proofProvider,
  }) : _client = client,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _endpoint = endpoint ?? defaultEndpoint,
       _timeout = timeout,
       _proofProvider = proofProvider ?? requestOpenIdProof;

  static final Uri defaultEndpoint = Uri.parse(
    BuildConfig.INTERGALACTIC_SOUNDBOARD_AUTHORITY_ENDPOINT.trim().isEmpty
        ? 'https://ourgalaxy.space/api/intergalactic/soundboard/v1'
        : BuildConfig.INTERGALACTIC_SOUNDBOARD_AUTHORITY_ENDPOINT,
  );

  final MatrixClient _client;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Uri _endpoint;
  final Duration _timeout;
  final SoundboardAuthorityProofProvider _proofProvider;

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  /// Mints a fresh OpenID proof from the homeserver for the current user.
  Future<SoundboardAuthorityOpenIdProof> currentProof() =>
      _proofProvider(_client);

  @override
  Future<SoundboardAuthorityResult<SoundboardAuthoritySpaceProtection>>
  enableSpaceProtection({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    int? memberUploadLevel,
  }) {
    return _postProtection('/spaces/enable', {
      'request_id': requestId,
      'auth': auth.toJson(),
      'source_space_id': sourceSpaceId,
      if (memberUploadLevel != null) 'member_upload_level': memberUploadLevel,
    });
  }

  @override
  Future<SoundboardAuthorityResult<SoundboardAuthoritySpaceProtection>>
  disableSpaceProtection({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
  }) {
    return _postProtection('/spaces/disable', {
      'request_id': requestId,
      'auth': auth.toJson(),
      'source_space_id': sourceSpaceId,
    });
  }

  @override
  Future<SoundboardAuthorityResult<SoundboardAuthorityPackState>> createPack(
    SoundboardAuthorityCreatePackRequest request,
  ) async {
    return _postPack('/packs/create', request.toJson());
  }

  @override
  Future<SoundboardAuthorityResult<SoundboardAuthorityPackState>> updatePack({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String packId,
    required int expectedRevision,
    String? name,
    String? emoji,
    bool? disabled,
  }) {
    return _postPack('/packs/update', {
      'request_id': requestId,
      'auth': auth.toJson(),
      'source_space_id': sourceSpaceId,
      'pack_id': packId,
      'expected_revision': expectedRevision,
      if (name != null) 'name': name,
      if (emoji != null) 'emoji': emoji,
      if (disabled != null) 'disabled': disabled,
    });
  }

  @override
  Future<SoundboardAuthorityResult<SoundboardAuthorityPackState>> deletePack({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String packId,
    required int expectedRevision,
  }) {
    return _postPack('/packs/delete', {
      'request_id': requestId,
      'auth': auth.toJson(),
      'source_space_id': sourceSpaceId,
      'pack_id': packId,
      'expected_revision': expectedRevision,
    });
  }

  @override
  Future<SoundboardAuthorityResult<void>> createSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required String packId,
    required SoundboardAuthoritySoundContent content,
  }) {
    return _postVoid('/sounds/create', {
      'request_id': requestId,
      'auth': auth.toJson(),
      'source_space_id': sourceSpaceId,
      'sound_id': soundId,
      'pack_id': packId,
      'sound': content.toJson(),
    });
  }

  @override
  Future<SoundboardAuthorityResult<void>> updateSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required int expectedRevision,
    int? volume,
  }) {
    return _postVoid('/sounds/update', {
      'request_id': requestId,
      'auth': auth.toJson(),
      'source_space_id': sourceSpaceId,
      'sound_id': soundId,
      'expected_revision': expectedRevision,
      if (volume != null)
        'sound': SoundboardAuthoritySoundContent.volumeOnly(volume),
    });
  }

  @override
  Future<SoundboardAuthorityResult<void>> moveSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required String packId,
    required int expectedRevision,
  }) {
    return _postVoid('/sounds/move', {
      'request_id': requestId,
      'auth': auth.toJson(),
      'source_space_id': sourceSpaceId,
      'sound_id': soundId,
      'pack_id': packId,
      'expected_revision': expectedRevision,
    });
  }

  @override
  Future<SoundboardAuthorityResult<void>> deleteSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required int expectedRevision,
  }) {
    return _postVoid('/sounds/delete', {
      'request_id': requestId,
      'auth': auth.toJson(),
      'source_space_id': sourceSpaceId,
      'sound_id': soundId,
      'expected_revision': expectedRevision,
    });
  }

  @override
  Future<SoundboardAuthorityResult<SoundboardPlaybackAuthorization>>
  createPlaybackAuthorization({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String destinationRoomId,
    required String callSessionId,
    required String packId,
    required String soundId,
  }) async {
    final decoded = await _post('/playback-authorizations/create', {
      'request_id': requestId,
      'auth': auth.toJson(),
      'source_space_id': sourceSpaceId,
      'destination_room_id': destinationRoomId,
      'call_session_id': callSessionId,
      'pack_id': packId,
      'sound_id': soundId,
    });
    return decoded.map((json) {
      final authorization = SoundboardPlaybackAuthorization.fromJson(
        json['authorization'] is Map
            ? Map<String, dynamic>.from(json['authorization'] as Map)
            : json,
      );
      return authorization;
    });
  }

  Future<SoundboardAuthorityResult<SoundboardAuthoritySpaceProtection>>
  _postProtection(String path, Map<String, Object?> body) async {
    final decoded = await _post(path, body);
    return decoded.map(SoundboardAuthoritySpaceProtection.fromJson);
  }

  Future<SoundboardAuthorityResult<SoundboardAuthorityPackState>> _postPack(
    String path,
    Map<String, Object?> body,
  ) async {
    final decoded = await _post(path, body);
    return decoded.map(
      (json) => SoundboardAuthorityPackResponse.fromJson(json)?.pack,
    );
  }

  Future<SoundboardAuthorityResult<void>> _postVoid(
    String path,
    Map<String, Object?> body,
  ) async {
    final decoded = await _post(path, body);
    return switch (decoded) {
      _RawSuccess() => const SoundboardAuthoritySuccess<void>(null),
      _RawFailure(error: final error) => SoundboardAuthorityFailure<void>(
        error,
      ),
    };
  }

  /// Sends the request and classifies the outcome into a raw success (decoded
  /// JSON body) or a structured failure. Network, TLS, and timeout problems
  /// fail closed as retryable `upstream_unavailable` rather than throwing, so
  /// callers only handle the sealed result.
  Future<_RawResult> _post(String path, Map<String, Object?> body) async {
    http.Response response;
    try {
      response = await _httpClient
          .post(
            _uri(path),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (_) {
      return _transportFailure(path);
    }
    return _classify(path, response);
  }

  @override
  Future<SoundboardAuthorityResult<List<SoundboardVerificationKey>>>
  fetchVerificationKeys() async {
    final result = await _get('/keys');
    return result.map<List<SoundboardVerificationKey>>((json) {
      final keys = SoundboardVerificationKey.listFromDocument(json);
      // An empty key set is a failure, not an empty success: with no key
      // nothing can be verified, and reporting "ok, zero keys" would let a
      // caller mistake an unusable response for a valid one.
      return keys.isEmpty ? null : keys;
    });
  }

  /// GET counterpart of [_post] for the one unauthenticated endpoint.
  ///
  /// Both verbs classify through [_classify], because the two hand-maintained
  /// copies this replaced had already drifted: the GET copy omitted the bare
  /// `error`-string fallback, so a non-enveloped error body on `/keys` reported
  /// `internal_error` while the same body on any POST path reported its real
  /// code.
  Future<_RawResult> _get(String path) async {
    http.Response response;
    try {
      response = await _httpClient
          .get(_uri(path), headers: const {'Accept': 'application/json'})
          .timeout(_timeout);
    } catch (_) {
      return _transportFailure(path);
    }
    return _classify(path, response);
  }

  /// Nothing came back at all — network, TLS, or timeout. Retryable by
  /// definition: no request outcome is known.
  _RawResult _transportFailure(String path) {
    Log.w(
      'soundboard authority request failed path=$path reason=transport',
      category: LogCategory.app,
      source: 'soundboard-authority',
    );
    return _RawFailure(
      const SoundboardAuthorityError(
        code: SoundboardAuthorityErrorCode.upstreamUnavailable,
        message: 'The soundboard service is unreachable.',
        retryable: true,
      ),
    );
  }

  /// Turns a response into a raw success (decoded JSON body) or a structured
  /// failure. An unparseable body is treated as an empty one rather than
  /// throwing, so callers only ever handle the sealed result.
  _RawResult _classify(String path, http.Response response) {
    Map<String, dynamic> json;
    final raw = response.body.trim();
    try {
      final decoded = raw.isEmpty ? const <String, dynamic>{} : jsonDecode(raw);
      json = decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
    } catch (_) {
      json = <String, dynamic>{};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _RawSuccess(json);
    }

    final error =
        SoundboardAuthorityError.fromJson(json) ??
        SoundboardAuthorityError(
          code:
              SoundboardAuthorityErrorCode.fromWire(json['error']) ??
              SoundboardAuthorityErrorCode.internalError,
          message: 'The soundboard request failed.',
          retryable: response.statusCode >= 500,
        );
    // The service message is user-safe by contract (never tokens, room names,
    // media, or raw upstream bodies — see the service "Error Contract") and is
    // the actionable half of a failure (e.g. "Grant the service user power
    // level N …"), so log it: a bare code hides why the request was rejected.
    Log.w(
      'soundboard authority request failed path=$path '
      'status=${response.statusCode} code=${error.code.wireValue} '
      'message=${error.message}',
      category: LogCategory.app,
      source: 'soundboard-authority',
    );
    return _RawFailure(error);
  }

  Uri _uri(String path) {
    final basePath = _endpoint.path.endsWith('/')
        ? _endpoint.path.substring(0, _endpoint.path.length - 1)
        : _endpoint.path;
    return _endpoint.replace(path: '$basePath$path');
  }

  /// Default proof provider: mints a homeserver OpenID token for the current
  /// user. This is the only credential handed to the service.
  static Future<SoundboardAuthorityOpenIdProof> requestOpenIdProof(
    MatrixClient client,
  ) async {
    final matrixClient = client.matrixClient;
    final userId = matrixClient.userID;
    if (userId == null || userId.trim().isEmpty) {
      throw StateError('This Matrix session does not have a user ID yet.');
    }
    final token = await matrixClient.requestOpenIdToken(userId, {});
    return SoundboardAuthorityOpenIdProof(
      matrixServerName: token.matrixServerName,
      openIdToken: token.accessToken,
    );
  }
}

/// Internal decode outcome before mapping to a typed [SoundboardAuthorityResult].
sealed class _RawResult {
  const _RawResult();

  /// Maps a successful JSON body to a typed value, or fails closed with
  /// `internal_error` when the expected field is missing/malformed.
  SoundboardAuthorityResult<T> map<T>(
    T? Function(Map<String, dynamic>) decode,
  ) {
    return switch (this) {
      _RawSuccess(json: final json) => _decodeSuccess(decode(json)),
      _RawFailure(error: final error) => SoundboardAuthorityFailure<T>(error),
    };
  }

  SoundboardAuthorityResult<T> _decodeSuccess<T>(T? value) {
    if (value == null) {
      return SoundboardAuthorityFailure<T>(
        const SoundboardAuthorityError(
          code: SoundboardAuthorityErrorCode.internalError,
          message: 'The soundboard service returned an unexpected response.',
          retryable: false,
        ),
      );
    }
    return SoundboardAuthoritySuccess<T>(value);
  }
}

class _RawSuccess extends _RawResult {
  const _RawSuccess(this.json);

  final Map<String, dynamic> json;
}

class _RawFailure extends _RawResult {
  const _RawFailure(this.error);

  final SoundboardAuthorityError error;
}
