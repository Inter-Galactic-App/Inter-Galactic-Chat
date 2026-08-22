import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/config/platform_utils.dart';

import 'matrix_client.dart';

typedef RecoveryKeyValidator = Future<void> Function(String recoveryKey);
typedef CryptoIdentityStateProvider
    = Future<({bool initialized, bool connected})> Function();
typedef ConnectedRecoverySecretValidator = Future<void> Function(
  String recoverySecret,
);
typedef CryptoIdentityRestorer = Future<void> Function(String recoverySecret);
typedef BiometricRecoveryKeyLogoutCallback = Future<void> Function();
typedef BiometricRecoveryKeyLogoutChoiceCallback
    = Future<BiometricRecoveryKeyLogoutChoice?> Function(
  BiometricRecoveryKeyStatus status,
);
typedef BiometricRecoveryKeyLogoutStorageFailureCallback = void Function(
  BiometricRecoveryKeyLogoutChoice choice,
  Object error,
  StackTrace stackTrace,
);

const _unreadableStoredRecoveryKeyMessage =
    'Stored recovery key cannot be unlocked, so sign-out was cancelled.';

enum BiometricRecoveryKeyValidationPath {
  connectedSecretStorage,
  restoreCryptoIdentity,
}

enum BiometricRecoveryKeyLogoutChoice {
  keep,
  delete,
  cancel,
}

class BiometricRecoveryKeyStoreException implements Exception {
  const BiometricRecoveryKeyStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BiometricRecoveryKeyStatus {
  const BiometricRecoveryKeyStatus({
    required this.supported,
    required this.biometricAvailable,
    required this.stored,
    required this.biometryType,
    this.unavailableReason,
    this.lastUpdatedAt,
    this.platform,
    this.biometricStrongAvailable,
    this.hardwareBacked,
    this.strongBoxBacked,
  });

  factory BiometricRecoveryKeyStatus.fromNative(Map<String, dynamic> value) {
    final lastUpdatedRaw = value['lastUpdatedAt'] as String?;
    return BiometricRecoveryKeyStatus(
      supported: value['supported'] == true,
      biometricAvailable: value['biometricAvailable'] == true,
      stored: value['stored'] == true,
      biometryType: (value['biometryType'] as String?) ?? 'none',
      unavailableReason: value['unavailableReason'] as String?,
      lastUpdatedAt:
          lastUpdatedRaw == null ? null : DateTime.tryParse(lastUpdatedRaw),
      platform: value['platform'] as String?,
      biometricStrongAvailable: value['biometricStrongAvailable'] as bool?,
      hardwareBacked: value['hardwareBacked'] as bool?,
      strongBoxBacked: value['strongBoxBacked'] as bool?,
    );
  }

  const BiometricRecoveryKeyStatus.unsupported(String reason)
      : supported = false,
        biometricAvailable = false,
        stored = false,
        biometryType = 'none',
        unavailableReason = reason,
        lastUpdatedAt = null,
        platform = null,
        biometricStrongAvailable = null,
        hardwareBacked = null,
        strongBoxBacked = null;

  final bool supported;
  final bool biometricAvailable;
  final bool stored;
  final String biometryType;
  final String? unavailableReason;
  final DateTime? lastUpdatedAt;
  final String? platform;
  final bool? biometricStrongAvailable;
  final bool? hardwareBacked;
  final bool? strongBoxBacked;

  bool get canStore => supported && biometricAvailable;
  bool get canRead =>
      canStore &&
      stored &&
      unavailableReason != 'biometry_changed_or_unavailable';

  String get promptLabel {
    return switch (biometryType) {
      'face_id' => 'Face ID',
      'touch_id' => 'Touch ID',
      'face_unlock' => 'Face Unlock',
      'fingerprint' => 'Fingerprint',
      'iris' => 'Iris Scan',
      _ => 'biometrics',
    };
  }
}

class BiometricRecoveryKeyValidation {
  const BiometricRecoveryKeyValidation._();

  static Future<BiometricRecoveryKeyValidationPath> validateForCurrentIdentity({
    required String recoverySecret,
    required CryptoIdentityStateProvider cryptoIdentityState,
    required ConnectedRecoverySecretValidator validateConnectedSecretStorage,
    required CryptoIdentityRestorer restoreCryptoIdentity,
  }) async {
    final state = await cryptoIdentityState();
    if (state.connected) {
      await validateConnectedSecretStorage(recoverySecret);
      return BiometricRecoveryKeyValidationPath.connectedSecretStorage;
    }

    await restoreCryptoIdentity(recoverySecret);
    return BiometricRecoveryKeyValidationPath.restoreCryptoIdentity;
  }
}

class BiometricRecoveryKeyLogoutFlow {
  const BiometricRecoveryKeyLogoutFlow._();

  static Future<bool> run({
    required BiometricRecoveryKeyLogoutChoice choice,
    required BiometricRecoveryKeyLogoutCallback ensureKeyPrepared,
    required BiometricRecoveryKeyLogoutCallback deleteKey,
    required BiometricRecoveryKeyLogoutCallback logout,
  }) async {
    switch (choice) {
      case BiometricRecoveryKeyLogoutChoice.keep:
        await ensureKeyPrepared();
        break;
      case BiometricRecoveryKeyLogoutChoice.delete:
        await deleteKey();
        break;
      case BiometricRecoveryKeyLogoutChoice.cancel:
        return false;
    }

    await logout();
    return true;
  }

  static Future<bool> runForStatus({
    required BiometricRecoveryKeyStatus status,
    required BiometricRecoveryKeyLogoutChoiceCallback requestChoice,
    required BiometricRecoveryKeyLogoutCallback ensureKeyPrepared,
    required BiometricRecoveryKeyLogoutCallback deleteKey,
    required BiometricRecoveryKeyLogoutCallback logout,
    BiometricRecoveryKeyLogoutStorageFailureCallback? onStorageFailure,
  }) async {
    if (!status.stored) {
      await logout();
      return true;
    }

    final choice = await requestChoice(status);
    if (choice == null || choice == BiometricRecoveryKeyLogoutChoice.cancel) {
      return false;
    }

    if (choice == BiometricRecoveryKeyLogoutChoice.keep && !status.canRead) {
      onStorageFailure?.call(
        choice,
        const BiometricRecoveryKeyStoreException(
          _unreadableStoredRecoveryKeyMessage,
        ),
        StackTrace.current,
      );
      return false;
    }

    try {
      switch (choice) {
        case BiometricRecoveryKeyLogoutChoice.keep:
          await ensureKeyPrepared();
          break;
        case BiometricRecoveryKeyLogoutChoice.delete:
          await deleteKey();
          break;
        case BiometricRecoveryKeyLogoutChoice.cancel:
          return false;
      }
    } catch (error, stackTrace) {
      onStorageFailure?.call(choice, error, stackTrace);
      return false;
    }

    await logout();
    return true;
  }
}

abstract class BiometricRecoveryKeyNativePlatform {
  Future<BiometricRecoveryKeyStatus> getStatus({required String accountKey});

  Future<void> writeRecoveryKey({
    required String accountKey,
    required String recoveryKey,
  });

  Future<String?> readRecoveryKey({
    required String accountKey,
    required String reason,
  });

  Future<void> deleteRecoveryKey({required String accountKey});

  Future<void> deleteAllRecoveryKeys();
}

class MethodChannelBiometricRecoveryKeyPlatform
    implements BiometricRecoveryKeyNativePlatform {
  const MethodChannelBiometricRecoveryKeyPlatform({
    MethodChannel channel =
        const MethodChannel('chat.intergalactic.app/secure_recovery_key'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<BiometricRecoveryKeyStatus> getStatus({
    required String accountKey,
  }) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'getStatus',
        <String, dynamic>{'accountKey': accountKey},
      );
      return BiometricRecoveryKeyStatus.fromNative(response ?? const {});
    } on MissingPluginException {
      return const BiometricRecoveryKeyStatus.unsupported('missing_plugin');
    } on PlatformException catch (error) {
      return BiometricRecoveryKeyStatus.unsupported(
        error.code.isEmpty ? 'platform_error' : error.code,
      );
    }
  }

  @override
  Future<void> writeRecoveryKey({
    required String accountKey,
    required String recoveryKey,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'writeRecoveryKey',
        <String, dynamic>{
          'accountKey': accountKey,
          'recoveryKey': recoveryKey,
        },
      );
    } on MissingPluginException {
      throw const BiometricRecoveryKeyStoreException(
        'Biometric recovery-key storage is not available on this platform.',
      );
    }
  }

  @override
  Future<String?> readRecoveryKey({
    required String accountKey,
    required String reason,
  }) async {
    try {
      final value = await _channel.invokeMethod<String>(
        'readRecoveryKey',
        <String, dynamic>{
          'accountKey': accountKey,
          'reason': reason,
        },
      );
      return value?.trim().isEmpty == true ? null : value;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      if (error.code == 'not_found' ||
          error.code == 'auth_failed' ||
          error.code == 'auth_cancelled' ||
          error.code == 'biometrics_unavailable' ||
          error.code == 'biometry_changed_or_unavailable') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteRecoveryKey({required String accountKey}) {
    return _channel.invokeMethod<void>(
      'deleteRecoveryKey',
      <String, dynamic>{'accountKey': accountKey},
    );
  }

  @override
  Future<void> deleteAllRecoveryKeys() async {
    try {
      await _channel.invokeMethod<void>('deleteAllRecoveryKeys');
    } on MissingPluginException {
      return;
    }
  }
}

class BiometricRecoveryKeyStore {
  BiometricRecoveryKeyStore({
    BiometricRecoveryKeyNativePlatform platform =
        const MethodChannelBiometricRecoveryKeyPlatform(),
    bool? isSupportedPlatformOverride,
    @visibleForTesting bool? isIOSOverride,
  })  : _platform = platform,
        _isSupportedPlatformOverride =
            isSupportedPlatformOverride ?? isIOSOverride;

  static final BiometricRecoveryKeyStore instance = BiometricRecoveryKeyStore();

  final BiometricRecoveryKeyNativePlatform _platform;
  final bool? _isSupportedPlatformOverride;

  bool get _isSupportedPlatform =>
      _isSupportedPlatformOverride ??
      (PlatformUtils.isIOS || PlatformUtils.isAndroid);

  Future<BiometricRecoveryKeyStatus> status(MatrixClient client) async {
    return statusForClientIncludingLegacy(client);
  }

  Future<BiometricRecoveryKeyStatus> statusForAccountKey(
    String accountKey,
  ) async {
    if (!_isSupportedPlatform) {
      return const BiometricRecoveryKeyStatus.unsupported(
        'unsupported_platform',
      );
    }
    return _platform.getStatus(accountKey: accountKey);
  }

  Future<void> validateAndSave(
    MatrixClient client,
    String recoveryKey, {
    required RecoveryKeyValidator validator,
  }) async {
    final accountKey = accountKeyForClient(client);
    if (accountKey == null) {
      throw const BiometricRecoveryKeyStoreException(
        'This account is not ready for local recovery-key storage yet.',
      );
    }
    await validateAndSaveForAccountKey(
      accountKey: accountKey,
      recoveryKey: recoveryKey,
      validator: validator,
    );
  }

  Future<void> validateAndSaveForAccountKey({
    required String accountKey,
    required String recoveryKey,
    required RecoveryKeyValidator validator,
  }) async {
    final normalizedRecoveryKey = recoveryKey.trim();
    if (!looksLikeRecoverySecret(normalizedRecoveryKey)) {
      throw const BiometricRecoveryKeyStoreException(
        'Enter a recovery key or security phrase before saving.',
      );
    }

    final currentStatus = await statusForAccountKey(accountKey);
    if (!currentStatus.supported) {
      throw const BiometricRecoveryKeyStoreException(
        'Biometric recovery-key storage is only available on supported iOS and Android devices.',
      );
    }
    if (!currentStatus.biometricAvailable) {
      throw const BiometricRecoveryKeyStoreException(
        'Biometric unlock is not available on this device.',
      );
    }

    await validator(normalizedRecoveryKey);
    await _platform.writeRecoveryKey(
      accountKey: accountKey,
      recoveryKey: normalizedRecoveryKey,
    );
  }

  Future<String?> read(
    MatrixClient client, {
    required String reason,
  }) async {
    final accountKey = accountKeyForClient(client);
    if (accountKey == null || !_isSupportedPlatform) {
      return null;
    }
    return readForAccountKeysIncludingLegacy(
      accountKey: accountKey,
      legacyAccountKey: legacyAccountKeyForClient(client),
      reason: reason,
    );
  }

  Future<void> delete(MatrixClient client) async {
    await deleteForClientIncludingLegacy(client);
  }

  Future<void> deleteAllLocalRecoveryKeys() async {
    if (!_isSupportedPlatform) {
      return;
    }
    await _platform.deleteAllRecoveryKeys();
  }

  Future<BiometricRecoveryKeyStatus> statusForClientIncludingLegacy(
    MatrixClient client,
  ) async {
    final accountKey = accountKeyForClient(client);
    if (accountKey == null) {
      return const BiometricRecoveryKeyStatus.unsupported(
        'missing_account_scope',
      );
    }
    return statusForAccountKeysIncludingLegacy(
      accountKey: accountKey,
      legacyAccountKey: legacyAccountKeyForClient(client),
    );
  }

  Future<void> ensureAccountScopedCopyForLogout(MatrixClient client) async {
    final accountKey = accountKeyForClient(client);
    if (accountKey == null || !_isSupportedPlatform) {
      return;
    }
    await ensureAccountScopedCopyForLogoutForAccountKeys(
      accountKey: accountKey,
      legacyAccountKey: legacyAccountKeyForClient(client),
    );
  }

  Future<void> deleteForClientIncludingLegacy(MatrixClient client) async {
    final accountKey = accountKeyForClient(client);
    if (accountKey == null || !_isSupportedPlatform) {
      return;
    }
    await deleteForAccountKeysIncludingLegacy(
      accountKey: accountKey,
      legacyAccountKey: legacyAccountKeyForClient(client),
    );
  }

  @visibleForTesting
  Future<BiometricRecoveryKeyStatus> statusForAccountKeysIncludingLegacy({
    required String accountKey,
    required String? legacyAccountKey,
  }) async {
    final currentStatus = await statusForAccountKey(accountKey);
    if (currentStatus.stored ||
        !currentStatus.supported ||
        legacyAccountKey == null ||
        legacyAccountKey == accountKey) {
      return currentStatus;
    }

    final legacyStatus = await statusForAccountKey(legacyAccountKey);
    return legacyStatus.stored ? legacyStatus : currentStatus;
  }

  @visibleForTesting
  Future<String?> readForAccountKeysIncludingLegacy({
    required String accountKey,
    required String? legacyAccountKey,
    required String reason,
  }) async {
    final currentStatus = await statusForAccountKey(accountKey);
    if (currentStatus.stored) {
      return _platform.readRecoveryKey(
        accountKey: accountKey,
        reason: reason,
      );
    }

    if (legacyAccountKey == null || legacyAccountKey == accountKey) {
      return null;
    }

    final legacyStatus = await statusForAccountKey(legacyAccountKey);
    if (!legacyStatus.stored) {
      return null;
    }

    return _platform.readRecoveryKey(
      accountKey: legacyAccountKey,
      reason: reason,
    );
  }

  @visibleForTesting
  Future<void> ensureAccountScopedCopyForLogoutForAccountKeys({
    required String accountKey,
    required String? legacyAccountKey,
  }) async {
    final currentStatus = await statusForAccountKey(accountKey);
    if (currentStatus.stored) {
      if (!currentStatus.canRead) {
        throw const BiometricRecoveryKeyStoreException(
          _unreadableStoredRecoveryKeyMessage,
        );
      }
      return;
    }

    if (legacyAccountKey == null || legacyAccountKey == accountKey) {
      return;
    }

    final legacyStatus = await statusForAccountKey(legacyAccountKey);
    if (!legacyStatus.stored) {
      return;
    }
    if (!legacyStatus.canRead) {
      throw const BiometricRecoveryKeyStoreException(
        _unreadableStoredRecoveryKeyMessage,
      );
    }

    String? recoveryKey = await _platform.readRecoveryKey(
      accountKey: legacyAccountKey,
      reason: 'Unlock your stored Matrix recovery key before signing out.',
    );
    if (recoveryKey == null) {
      throw const BiometricRecoveryKeyStoreException(
        'Stored recovery key was not unlocked, so sign-out was cancelled.',
      );
    }

    try {
      await _platform.writeRecoveryKey(
        accountKey: accountKey,
        recoveryKey: recoveryKey,
      );
      await _platform.deleteRecoveryKey(accountKey: legacyAccountKey);
    } finally {
      recoveryKey = null;
    }
  }

  @visibleForTesting
  Future<void> deleteForAccountKeysIncludingLegacy({
    required String accountKey,
    required String? legacyAccountKey,
  }) async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> deleteKey(String key) async {
      try {
        await _platform.deleteRecoveryKey(accountKey: key);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await deleteKey(accountKey);
    if (legacyAccountKey != null && legacyAccountKey != accountKey) {
      await deleteKey(legacyAccountKey);
    }

    final error = firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, firstStackTrace ?? StackTrace.current);
    }
  }

  @visibleForTesting
  static bool looksLikeRecoverySecret(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 16) {
      return false;
    }
    if (trimmed.contains('\n') || trimmed.contains('\r')) {
      return false;
    }
    return true;
  }

  @visibleForTesting
  static String? accountKeyForClient(MatrixClient client) {
    final matrixClient = client.getMatrixClient();
    return accountKeyForParts(
      homeserver: matrixClient.homeserver ?? matrixClient.baseUri,
      userId: matrixClient.userID,
    );
  }

  @visibleForTesting
  static String? accountKeyForParts({
    required Uri? homeserver,
    required String? userId,
    // Kept for source compatibility with v1 callers/tests. v2 intentionally
    // scopes stored keys to the account rather than the Matrix device.
    String? deviceId,
  }) {
    final homeserverKey = _normalizeHomeserver(homeserver);
    final normalizedUserId = userId?.trim().toLowerCase();

    if (homeserverKey == null ||
        normalizedUserId == null ||
        normalizedUserId.isEmpty) {
      return null;
    }

    final rawScope = '$homeserverKey|$normalizedUserId';
    return 'matrix_recovery_key.v2.${sha256.convert(utf8.encode(rawScope))}';
  }

  @visibleForTesting
  static String? legacyAccountKeyForClient(MatrixClient client) {
    final matrixClient = client.getMatrixClient();
    return legacyAccountKeyForParts(
      homeserver: matrixClient.homeserver ?? matrixClient.baseUri,
      userId: matrixClient.userID,
      deviceId: matrixClient.deviceID,
    );
  }

  @visibleForTesting
  static String? legacyAccountKeyForParts({
    required Uri? homeserver,
    required String? userId,
    required String? deviceId,
  }) {
    final homeserverKey = _normalizeHomeserver(homeserver);
    final normalizedUserId = userId?.trim().toLowerCase();
    final normalizedDeviceId = deviceId?.trim().toUpperCase();

    if (homeserverKey == null ||
        normalizedUserId == null ||
        normalizedUserId.isEmpty ||
        normalizedDeviceId == null ||
        normalizedDeviceId.isEmpty) {
      return null;
    }

    final rawScope = '$homeserverKey|$normalizedUserId|$normalizedDeviceId';
    return 'matrix_recovery_key.v1.${sha256.convert(utf8.encode(rawScope))}';
  }

  static String? _normalizeHomeserver(Uri? homeserver) {
    if (homeserver == null) {
      return null;
    }
    if (homeserver.scheme.isNotEmpty && homeserver.host.isNotEmpty) {
      final port = homeserver.hasPort ? ':${homeserver.port}' : '';
      return '${homeserver.scheme.toLowerCase()}://'
          '${homeserver.host.toLowerCase()}$port';
    }
    final raw = homeserver.toString().trim().toLowerCase();
    return raw.isEmpty ? null : raw;
  }
}
