import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix_api_lite.dart' as matrix_api;

class MatrixE2eeDiagnostics {
  MatrixE2eeDiagnostics({
    required matrix.Client client,
    required String clientId,
    bool suppressAutomaticRepair = false,
  })  : _client = client,
        _clientId = clientId,
        _suppressAutomaticRepair = suppressAutomaticRepair;

  static const String policyCrossVerifiedIfEnabled =
      'cross_verified_if_enabled';
  static const String policyAllNonBlocked = 'all_non_blocked';
  static const String policyCrossVerified = 'cross_verified';
  static const String policyDirectlyVerifiedOnly = 'directly_verified_only';
  static const List<String> keySharingPolicyValues = <String>[
    policyCrossVerifiedIfEnabled,
    policyAllNonBlocked,
    policyCrossVerified,
    policyDirectlyVerifiedOnly,
  ];
  static const Duration _ignoredCallMemberLogInterval = Duration(minutes: 5);

  static bool _sdkLogBridgeInstalled = false;
  static DateTime? _lastIgnoredCallMemberLogAt;
  static int _ignoredCallMemberLogCount = 0;

  final matrix.Client _client;
  final String _clientId;
  final bool _suppressAutomaticRepair;
  final Map<String, DateTime> _lastTimelineRequestLog = <String, DateTime>{};

  StreamSubscription<matrix.Event>? _timelineSubscription;
  StreamSubscription<matrix.Event>? _historySubscription;
  StreamSubscription<matrix.ToDeviceEvent>? _toDeviceSubscription;
  StreamSubscription<matrix.SdkError>? _encryptionErrorSubscription;
  StreamSubscription<String>? _keySharingPolicySubscription;
  Future<void>? _olmRepairInFlight;
  DateTime? _lastOlmRepairAt;
  bool? _cryptoIdentityInitialized;
  bool? _cryptoIdentityConnected;
  bool? _keyBackupCached;
  bool? _crossSigningCached;

  void start() {
    _installSdkLogBridge();
    applyConfiguredShareKeysWith();
    _keySharingPolicySubscription ??= preferences
        .matrixKeySharingPolicy.onChanged
        .listen((_) => applyConfiguredShareKeysWith());
    _timelineSubscription ??=
        _client.onTimelineEvent.stream.listen(_recordTimelineEvent);
    _historySubscription ??= _client.onHistoryEvent.stream.listen(
      (event) => _recordTimelineEvent(event, source: 'history'),
    );
    _toDeviceSubscription ??=
        _client.onToDeviceEvent.stream.listen(_recordToDeviceEvent);
    _encryptionErrorSubscription ??=
        _client.onEncryptionError.stream.listen(_recordEncryptionError);
  }

  Future<void> dispose() async {
    final subscriptions = <StreamSubscription<dynamic>?>[
      _timelineSubscription,
      _historySubscription,
      _toDeviceSubscription,
      _encryptionErrorSubscription,
      _keySharingPolicySubscription,
    ];
    _timelineSubscription = null;
    _historySubscription = null;
    _toDeviceSubscription = null;
    _encryptionErrorSubscription = null;
    _keySharingPolicySubscription = null;

    for (final subscription in subscriptions) {
      await subscription?.cancel();
    }
  }

  matrix.ShareKeysWith applyConfiguredShareKeysWith() {
    final policy = shareKeysWithForPreference(
      preferences.matrixKeySharingPolicy.value,
    );
    if (_client.shareKeysWith != policy) {
      _client.shareKeysWith = policy;
      Log.i(
        'Matrix E2EE key-sharing policy applied: ${policy.name}',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    } else {
      Log.d(
        'Matrix E2EE key-sharing policy unchanged: ${policy.name}',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    }
    return policy;
  }

  MatrixE2eeTrustStatus buildTrustStatus() {
    final userId = _client.userID;
    final deviceId = _client.deviceID;
    final ownKeys =
        userId == null ? null : _client.userDeviceKeys[userId]?.deviceKeys;
    final ownDevices = ownKeys?.values.toList() ?? <matrix.DeviceKeys>[];
    final currentDeviceKeys = deviceId == null ? null : ownKeys?[deviceId];
    final masterKey =
        userId == null ? null : _client.userDeviceKeys[userId]?.masterKey;

    return MatrixE2eeTrustStatus(
      clientIdHash: _hash(_clientId),
      userIdHash: _hash(userId),
      deviceId: deviceId,
      encryptionAvailable:
          _client.encryptionEnabled && _client.encryption != null,
      crossSigningEnabled: _client.encryption?.crossSigning.enabled ?? false,
      keyBackupEnabled: _client.encryption?.keyManager.enabled ?? false,
      cryptoIdentityInitialized: _cryptoIdentityInitialized,
      cryptoIdentityConnected: _cryptoIdentityConnected,
      keyBackupCached: _keyBackupCached,
      crossSigningCached: _crossSigningCached,
      keySharingPolicy: preferenceForShareKeysWith(_client.shareKeysWith),
      masterKeyAvailable: masterKey != null,
      masterKeyVerified: masterKey?.verified,
      currentDeviceKnown: currentDeviceKeys != null,
      currentDeviceVerified: currentDeviceKeys?.verified,
      currentDeviceCrossVerified: currentDeviceKeys?.crossVerified,
      currentDeviceDirectVerified: currentDeviceKeys?.directVerified,
      currentDeviceBlocked: currentDeviceKeys?.blocked,
      ownDeviceCount: ownDevices.length,
      verifiedOwnDeviceCount:
          ownDevices.where((device) => device.verified).length,
      blockedOwnDeviceCount:
          ownDevices.where((device) => device.blocked).length,
      encryptableOwnDeviceCount:
          ownDevices.where((device) => device.encryptToDevice).length,
    );
  }

  Future<void> refreshOwnDeviceKeys() async {
    final userId = _client.userID;
    if (userId == null || !_client.isLogged()) {
      return;
    }

    try {
      await _client.updateUserDeviceKeys(additionalUsers: {userId});
      await _refreshRecoveryState(reason: 'security_refresh');
      Log.d(
        'Refreshed local Matrix device-key status for E2EE diagnostics',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Failed to refresh local Matrix device keys for Security',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    }
  }

  Future<void> _refreshRecoveryState({
    required String reason,
  }) async {
    final encryption = _client.encryption;
    if (!_client.encryptionEnabled ||
        encryption == null ||
        !_client.isLogged()) {
      _cryptoIdentityInitialized = false;
      _cryptoIdentityConnected = false;
      _keyBackupCached = false;
      _crossSigningCached = false;
      return;
    }

    try {
      final cryptoIdentityState = await _client
          .getCryptoIdentityState()
          .timeout(const Duration(seconds: 8));
      final keyBackupCached = await encryption.keyManager
          .isCached()
          .timeout(const Duration(seconds: 8));
      final crossSigningCached = await encryption.crossSigning
          .isCached()
          .timeout(const Duration(seconds: 8));

      _cryptoIdentityInitialized = cryptoIdentityState.initialized;
      _cryptoIdentityConnected = cryptoIdentityState.connected;
      _keyBackupCached = keyBackupCached;
      _crossSigningCached = crossSigningCached;

      Log.d(
        'Matrix E2EE recovery state refreshed reason=$reason '
        'identity_initialized=${cryptoIdentityState.initialized} '
        'identity_connected=${cryptoIdentityState.connected} '
        'key_backup_cached=$keyBackupCached '
        'cross_signing_cached=$crossSigningCached',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Failed to refresh Matrix E2EE recovery state',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    }
  }

  Future<void> repairOlmToDevicePath({
    required String reason,
    bool includeSync = false,
    bool force = false,
  }) async {
    final runningRepair = _olmRepairInFlight;
    if (runningRepair != null) {
      Log.i(
        'Waiting for existing Matrix E2EE repair before starting reason=$reason',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
      await runningRepair;
      return;
    }

    final now = DateTime.now();
    if (!force &&
        _lastOlmRepairAt != null &&
        now.difference(_lastOlmRepairAt!) < const Duration(minutes: 5)) {
      Log.w(
        'Skipping Matrix E2EE repair reason=$reason because one ran recently',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
      return;
    }

    final repair = _runOlmToDeviceRepair(
      reason: reason,
      includeSync: includeSync,
    );
    _olmRepairInFlight = repair;
    _lastOlmRepairAt = now;
    try {
      await repair;
    } finally {
      if (identical(_olmRepairInFlight, repair)) {
        _olmRepairInFlight = null;
      }
    }
  }

  Future<void> _runOlmToDeviceRepair({
    required String reason,
    required bool includeSync,
  }) async {
    final encryption = _client.encryption;
    if (!_client.encryptionEnabled ||
        encryption == null ||
        !_client.isLogged()) {
      Log.w(
        'Skipping Matrix E2EE repair reason=$reason because encryption is unavailable',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
      return;
    }

    Log.w(
      'Starting Matrix E2EE repair reason=$reason include_sync=$includeSync',
      category: LogCategory.matrix,
      source: 'matrix-e2ee',
    );

    try {
      await encryption.olmManager
          .uploadKeys(oldKeyCount: 0, unusedFallbackKey: true)
          .timeout(const Duration(seconds: 12));
      Log.i(
        'Matrix E2EE repair uploaded fresh one-time/fallback keys',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Matrix E2EE repair could not refresh one-time/fallback keys',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    }

    try {
      await encryption.ssss
          .periodicallyRequestMissingCache()
          .timeout(const Duration(seconds: 8));
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Matrix E2EE repair could not refresh SSSS cache',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    }

    await _refreshRecoveryState(reason: 'repair_$reason');

    if (!includeSync) {
      return;
    }

    try {
      await _client.oneShotSync(timeout: const Duration(seconds: 8));
      Log.i(
        'Matrix E2EE repair completed a bounded sync',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Matrix E2EE repair bounded sync did not complete',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    }
  }

  void _recordTimelineEvent(
    matrix.Event event, {
    String source = 'timeline',
  }) {
    if (event.type != matrix.EventTypes.Encrypted ||
        event.messageType != matrix.MessageTypes.BadEncrypted) {
      return;
    }

    final canRequestSession = event.content['can_request_session'] == true;
    final reason = _classifyErrorText(event.content['body']?.toString());
    final roomId = event.room.id;
    final sessionId = _stringValue(event.content['session_id']);
    final senderKey = _stringValue(event.content['sender_key']);
    Log.w(
      'E2EE decrypt failure source=$source '
      'client=${_hash(_clientId)} room=${_hash(roomId)} '
      'event=${_hash(event.eventId)} sender=${_hash(event.senderId)} '
      'session=${_hash(sessionId)} sender_key=${_hash(senderKey)} '
      'can_request_session=$canRequestSession reason=$reason',
      category: LogCategory.matrix,
      source: 'matrix-e2ee',
    );

    if (canRequestSession) {
      _logRequestableSessionKey(event, source: source);
    }
  }

  void _logRequestableSessionKey(
    matrix.Event event, {
    required String source,
  }) {
    final roomId = event.room.id;
    final sessionId = _stringValue(event.content['session_id']);
    final key = '$roomId|$sessionId|${event.senderId}';
    final now = DateTime.now();
    final lastLog = _lastTimelineRequestLog[key];
    if (lastLog != null &&
        now.difference(lastLog) < const Duration(minutes: 2)) {
      return;
    }
    _lastTimelineRequestLog[key] = now;

    Log.i(
      'E2EE missing room session is requestable source=$source '
      'room=${_hash(roomId)} session=${_hash(sessionId)} '
      'sender=${_hash(event.senderId)}',
      category: LogCategory.matrix,
      source: 'matrix-e2ee',
    );
  }

  void _recordToDeviceEvent(matrix.ToDeviceEvent event) {
    switch (event.type) {
      case matrix.EventTypes.RoomKey:
      case matrix.EventTypes.ForwardedRoomKey:
        Log.i(
          'E2EE to-device key received type=${event.type} '
          'sender=${_hash(event.sender)} '
          'room=${_hash(_stringValue(event.content['room_id']))} '
          'session=${_hash(_stringValue(event.content['session_id']))} '
          'encrypted=${event.encryptedContent != null}',
          category: LogCategory.matrix,
          source: 'matrix-e2ee',
        );
        break;
      case matrix.EventTypes.RoomKeyRequest:
        final body = event.content['body'];
        final bodyMap = body is Map ? body : const <Object?, Object?>{};
        Log.i(
          'E2EE room-key request action=${_stringValue(event.content['action'])} '
          'sender=${_hash(event.sender)} '
          'requesting_device=${_hash(_stringValue(event.content['requesting_device_id']))} '
          'room=${_hash(_stringValue(bodyMap['room_id']))} '
          'session=${_hash(_stringValue(bodyMap['session_id']))}',
          category: LogCategory.matrix,
          source: 'matrix-e2ee',
        );
        break;
      case 'm.room_key.withheld':
        Log.w(
          'E2EE room key withheld sender=${_hash(event.sender)} '
          'room=${_hash(_stringValue(event.content['room_id']))} '
          'session=${_hash(_stringValue(event.content['session_id']))} '
          'code=${_compact(_stringValue(event.content['code']))} '
          'reason=${_compact(_stringValue(event.content['reason']))}',
          category: LogCategory.matrix,
          source: 'matrix-e2ee',
        );
        break;
      default:
        break;
    }
  }

  void _recordEncryptionError(matrix.SdkError error) {
    final text = error.exception.toString();
    final reason = _classifyErrorText(text);
    Log.w(
      'Matrix E2EE encryption error reason=$reason '
      'exception=${_compact(_exceptionName(error.exception))}',
      category: LogCategory.matrix,
      source: 'matrix-e2ee',
    );

    final repairable = reason == 'unknown_one_time_key' ||
        reason == 'unable_to_decrypt_olm' ||
        reason == 'olm_decryption_failed';
    if (repairable && _suppressAutomaticRepair) {
      Log.w(
        'Skipping automatic Matrix E2EE repair reason=$reason in a bounded notification bubble context',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
      return;
    }

    if (repairable) {
      unawaited(repairOlmToDevicePath(reason: reason));
    }
  }

  static matrix.ShareKeysWith shareKeysWithForPreference(String value) {
    switch (value) {
      case policyAllNonBlocked:
        return matrix.ShareKeysWith.all;
      case policyCrossVerified:
        return matrix.ShareKeysWith.crossVerified;
      case policyDirectlyVerifiedOnly:
        return matrix.ShareKeysWith.directlyVerifiedOnly;
      case policyCrossVerifiedIfEnabled:
      default:
        return matrix.ShareKeysWith.crossVerifiedIfEnabled;
    }
  }

  static String preferenceForShareKeysWith(matrix.ShareKeysWith value) {
    switch (value) {
      case matrix.ShareKeysWith.all:
        return policyAllNonBlocked;
      case matrix.ShareKeysWith.crossVerified:
        return policyCrossVerified;
      case matrix.ShareKeysWith.directlyVerifiedOnly:
        return policyDirectlyVerifiedOnly;
      case matrix.ShareKeysWith.crossVerifiedIfEnabled:
        return policyCrossVerifiedIfEnabled;
    }
  }

  static void _installSdkLogBridge() {
    if (_sdkLogBridgeInstalled) {
      return;
    }
    _sdkLogBridgeInstalled = true;
    matrix.Logs().onLog = _recordSdkLog;
  }

  static void _recordSdkLog(matrix_api.LogEvent event) {
    final title = event.title;
    final formattedException = event.exception?.toString();
    final reason = _classifyErrorText('$title ${formattedException ?? ''}');

    if (_isIgnorableCallMemberLog(title)) {
      _recordIgnoredCallMemberLog();
      return;
    }

    if (title.startsWith('[Vodozemac] Could not decrypt to device event')) {
      Log.w(
        'Matrix SDK to-device decrypt failure '
        'sender=${_hash(_extractSenderFromVodozemacLog(title))} '
        'reason=$reason exception=${_compact(_exceptionName(event.exception))}',
        category: LogCategory.matrix,
        source: 'matrix-sdk',
      );
      return;
    }

    if (event.level.index <= matrix_api.Level.warning.index) {
      Log.w(
        'Matrix SDK ${event.level.name}: ${_safeSdkTitle(title)}'
        '${formattedException == null ? '' : ' exception=${_compact(_exceptionName(event.exception))}'}',
        category: LogCategory.matrix,
        source: 'matrix-sdk',
      );
    } else if (reason != 'other') {
      Log.d(
        'Matrix SDK ${event.level.name}: ${_safeSdkTitle(title)} reason=$reason',
        category: LogCategory.matrix,
        source: 'matrix-sdk',
      );
    }
  }

  static bool _isIgnorableCallMemberLog(String title) {
    final lower = title.toLowerCase();
    return lower
            .contains('ignoring call event org.matrix.msc3401.call.member') &&
        lower.contains('because we do not have the call');
  }

  static void _recordIgnoredCallMemberLog() {
    _ignoredCallMemberLogCount++;
    final now = DateTime.now();
    final last = _lastIgnoredCallMemberLogAt;
    if (last != null && now.difference(last) < _ignoredCallMemberLogInterval) {
      return;
    }

    Log.d(
      'Suppressed Matrix SDK call-member warning spam '
      'count=$_ignoredCallMemberLogCount',
      category: LogCategory.matrix,
      source: 'matrix-sdk',
    );
    _ignoredCallMemberLogCount = 0;
    _lastIgnoredCallMemberLogAt = now;
  }

  static String? _extractSenderFromVodozemacLog(String title) {
    final match = RegExp(r'from\s+([^\s]+)\s+with content').firstMatch(title);
    return match?.group(1);
  }

  static String _safeSdkTitle(String title) {
    final cleaned = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    final sensitiveMarker = RegExp(
      r'\b(with content|content=|content:|ciphertext|session_key|sender_key)\b',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (sensitiveMarker == null) {
      return _compact(cleaned);
    }

    final prefix = cleaned.substring(0, sensitiveMarker.start).trim();
    if (prefix.isEmpty) {
      return '[sdk details redacted]';
    }
    return _compact('$prefix [sdk details redacted]');
  }

  static String _classifyErrorText(String? text) {
    final lower = text?.toLowerCase() ?? '';
    if (lower.contains('unknown one-time key')) {
      return 'unknown_one_time_key';
    }
    if (lower.contains('the sender has not sent us the session key') ||
        lower.contains('unknown inbound group session') ||
        lower.contains('unknown session')) {
      return 'missing_room_session';
    }
    if (lower.contains('m.unverified') ||
        lower.contains('unverified device') ||
        lower.contains('not verified')) {
      return 'unverified_or_withheld';
    }
    if (lower.contains('unabletodecryptwithanyolmsession') ||
        lower.contains('unable to decrypt with any olm session')) {
      return 'unable_to_decrypt_olm';
    }
    if (lower.contains('decryption failed')) {
      return 'olm_decryption_failed';
    }
    if (lower.contains('channel corrupted') ||
        lower.contains('corrupted session')) {
      return 'corrupted_session';
    }
    if (lower.contains('is not sent for this device')) {
      return 'not_sent_for_this_device';
    }
    return 'other';
  }

  static String _exceptionName(Object? exception) {
    if (exception == null) {
      return 'none';
    }
    final text = exception.toString();
    final parenIndex = text.indexOf('(');
    final colonIndex = text.indexOf(':');
    final splitIndex = [parenIndex, colonIndex]
        .where((index) => index > 0)
        .fold<int>(text.length, (min, index) => index < min ? index : min);
    return text.substring(0, splitIndex);
  }

  static String? _stringValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  static String _compact(String? value, {int max = 96}) {
    if (value == null || value.isEmpty) {
      return 'none';
    }
    final cleaned =
        Log.redactSensitiveInfo(value).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= max) {
      return cleaned;
    }
    return '${cleaned.substring(0, max)}...';
  }

  static String _hash(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) {
      return 'none';
    }
    return sha256.convert(utf8.encode(text)).toString().substring(0, 12);
  }
}

class MatrixE2eeTrustStatus {
  const MatrixE2eeTrustStatus({
    required this.clientIdHash,
    required this.userIdHash,
    required this.deviceId,
    required this.encryptionAvailable,
    required this.crossSigningEnabled,
    required this.keyBackupEnabled,
    required this.cryptoIdentityInitialized,
    required this.cryptoIdentityConnected,
    required this.keyBackupCached,
    required this.crossSigningCached,
    required this.keySharingPolicy,
    required this.masterKeyAvailable,
    required this.masterKeyVerified,
    required this.currentDeviceKnown,
    required this.currentDeviceVerified,
    required this.currentDeviceCrossVerified,
    required this.currentDeviceDirectVerified,
    required this.currentDeviceBlocked,
    required this.ownDeviceCount,
    required this.verifiedOwnDeviceCount,
    required this.blockedOwnDeviceCount,
    required this.encryptableOwnDeviceCount,
  });

  final String clientIdHash;
  final String userIdHash;
  final String? deviceId;
  final bool encryptionAvailable;
  final bool crossSigningEnabled;
  final bool keyBackupEnabled;
  final bool? cryptoIdentityInitialized;
  final bool? cryptoIdentityConnected;
  final bool? keyBackupCached;
  final bool? crossSigningCached;
  final String keySharingPolicy;
  final bool masterKeyAvailable;
  final bool? masterKeyVerified;
  final bool currentDeviceKnown;
  final bool? currentDeviceVerified;
  final bool? currentDeviceCrossVerified;
  final bool? currentDeviceDirectVerified;
  final bool? currentDeviceBlocked;
  final int ownDeviceCount;
  final int verifiedOwnDeviceCount;
  final int blockedOwnDeviceCount;
  final int encryptableOwnDeviceCount;

  bool get currentDeviceHealthy =>
      encryptionAvailable &&
      currentDeviceKnown &&
      currentDeviceBlocked != true &&
      (currentDeviceVerified == true || !crossSigningEnabled);

  bool get needsRecoveryKeyForHistory =>
      keyBackupEnabled &&
      (keyBackupCached == false || cryptoIdentityConnected == false);

  String get currentDeviceSummary {
    if (!encryptionAvailable) {
      return 'Encryption is unavailable in this session.';
    }
    if (!currentDeviceKnown) {
      return 'This session key has not loaded yet.';
    }
    if (currentDeviceBlocked == true) {
      return 'This session is blocked.';
    }
    if (needsRecoveryKeyForHistory && currentDeviceVerified == true) {
      return 'This session is verified, but old messages may still need your recovery key.';
    }
    if (needsRecoveryKeyForHistory) {
      return 'Enter your recovery key to unlock backed-up message keys for this session.';
    }
    if (currentDeviceVerified == true) {
      return 'This session is verified.';
    }
    if (crossSigningEnabled) {
      return 'This session is not verified, so some senders may not share keys with it.';
    }
    return 'This session can receive keys, but cross signing is not enabled.';
  }
}
