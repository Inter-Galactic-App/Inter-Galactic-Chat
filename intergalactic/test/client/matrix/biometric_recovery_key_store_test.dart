import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/biometric_recovery_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BiometricRecoveryKeyStore', () {
    test('scopes v2 account keys without exposing account identifiers', () {
      final key = BiometricRecoveryKeyStore.accountKeyForParts(
        homeserver: Uri.parse('https://matrix.example'),
        userId: '@Alice:Example',
        deviceId: 'mobile1',
      );

      expect(key, startsWith('matrix_recovery_key.v2.'));
      expect(key, isNot(contains('Alice')));
      expect(key, isNot(contains('matrix.example')));
      expect(key, isNot(contains('mobile1')));
      expect(
        key,
        BiometricRecoveryKeyStore.accountKeyForParts(
          homeserver: Uri.parse('https://matrix.example/ignored/path'),
          userId: '@alice:example',
          deviceId: 'new-device',
        ),
      );
    });

    test('uses different v2 keys for different users and homeservers', () {
      final first = BiometricRecoveryKeyStore.accountKeyForParts(
        homeserver: Uri.parse('https://matrix.example'),
        userId: '@alice:example',
        deviceId: 'DEVICE1',
      );
      final otherUser = BiometricRecoveryKeyStore.accountKeyForParts(
        homeserver: Uri.parse('https://matrix.example'),
        userId: '@bob:example',
        deviceId: 'DEVICE1',
      );
      final otherServer = BiometricRecoveryKeyStore.accountKeyForParts(
        homeserver: Uri.parse('https://other.example'),
        userId: '@alice:example',
        deviceId: 'DEVICE1',
      );

      expect(first, isNot(otherUser));
      expect(first, isNot(otherServer));
    });

    test('keeps legacy v1 current-device scope for fallback cleanup', () {
      final key = BiometricRecoveryKeyStore.legacyAccountKeyForParts(
        homeserver: Uri.parse('https://matrix.example'),
        userId: '@Alice:Example',
        deviceId: 'mobile1',
      );

      expect(key, startsWith('matrix_recovery_key.v1.'));
      expect(key, isNot(contains('Alice')));
      expect(key, isNot(contains('matrix.example')));
      expect(key, isNot(contains('mobile1')));
      expect(
        key,
        BiometricRecoveryKeyStore.legacyAccountKeyForParts(
          homeserver: Uri.parse('https://matrix.example/ignored/path'),
          userId: '@alice:example',
          deviceId: 'MOBILE1',
        ),
      );
    });

    test('reports unsupported outside supported mobile platforms', () async {
      final platform = _FakeBiometricRecoveryKeyPlatform();
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: false,
      );

      final status = await store.statusForAccountKey('account');

      expect(status.supported, isFalse);
      expect(status.unavailableReason, 'unsupported_platform');
      expect(platform.statusCalls, 0);
    });

    test('supports Android status metadata from the native bridge', () async {
      final platform = _FakeBiometricRecoveryKeyPlatform()
        ..status = const BiometricRecoveryKeyStatus(
          supported: true,
          biometricAvailable: true,
          stored: true,
          biometryType: 'fingerprint',
          platform: 'android',
          biometricStrongAvailable: true,
          hardwareBacked: true,
          strongBoxBacked: false,
        );
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );

      final status = await store.statusForAccountKey('account');

      expect(status.supported, isTrue);
      expect(status.platform, 'android');
      expect(status.promptLabel, 'Fingerprint');
      expect(status.biometricStrongAvailable, isTrue);
      expect(status.hardwareBacked, isTrue);
      expect(status.strongBoxBacked, isFalse);
    });

    test('uses platform-aware prompt labels', () {
      const labels = {
        'face_id': 'Face ID',
        'touch_id': 'Touch ID',
        'face_unlock': 'Face Unlock',
        'fingerprint': 'Fingerprint',
        'iris': 'Iris Scan',
        'biometric': 'biometrics',
      };

      for (final entry in labels.entries) {
        final status = BiometricRecoveryKeyStatus(
          supported: true,
          biometricAvailable: true,
          stored: false,
          biometryType: entry.key,
        );
        expect(status.promptLabel, entry.value);
      }
    });

    test('validates before writing recovery key', () async {
      final platform = _FakeBiometricRecoveryKeyPlatform();
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );
      final calls = <String>[];

      await store.validateAndSaveForAccountKey(
        accountKey: 'account',
        recoveryKey: 'ABCD EFGH IJKM NPQR STUV WXYZ 1234 5678',
        validator: (recoveryKey) async {
          calls.add('validate:$recoveryKey');
        },
      );

      expect(calls, ['validate:ABCD EFGH IJKM NPQR STUV WXYZ 1234 5678']);
      expect(platform.writes,
          {'account': 'ABCD EFGH IJKM NPQR STUV WXYZ 1234 5678'});
    });

    test('validates already connected crypto identity without restoring',
        () async {
      final calls = <String>[];

      final path =
          await BiometricRecoveryKeyValidation.validateForCurrentIdentity(
        recoverySecret: 'valid recovery secret',
        cryptoIdentityState: () async => (initialized: true, connected: true),
        validateConnectedSecretStorage: (recoverySecret) async {
          calls.add('connected:$recoverySecret');
        },
        restoreCryptoIdentity: (recoverySecret) async {
          calls.add('restore:$recoverySecret');
        },
      );

      expect(
        path,
        BiometricRecoveryKeyValidationPath.connectedSecretStorage,
      );
      expect(calls, ['connected:valid recovery secret']);
    });

    test('restores crypto identity when it is not connected', () async {
      final calls = <String>[];

      final path =
          await BiometricRecoveryKeyValidation.validateForCurrentIdentity(
        recoverySecret: 'valid recovery secret',
        cryptoIdentityState: () async => (initialized: true, connected: false),
        validateConnectedSecretStorage: (recoverySecret) async {
          calls.add('connected:$recoverySecret');
        },
        restoreCryptoIdentity: (recoverySecret) async {
          calls.add('restore:$recoverySecret');
        },
      );

      expect(
        path,
        BiometricRecoveryKeyValidationPath.restoreCryptoIdentity,
      );
      expect(calls, ['restore:valid recovery secret']);
    });

    test('does not restore when connected secret validation fails', () async {
      final calls = <String>[];

      await expectLater(
        BiometricRecoveryKeyValidation.validateForCurrentIdentity(
          recoverySecret: 'invalid recovery secret',
          cryptoIdentityState: () async => (initialized: true, connected: true),
          validateConnectedSecretStorage: (recoverySecret) async {
            calls.add('connected:$recoverySecret');
            throw Exception('invalid');
          },
          restoreCryptoIdentity: (recoverySecret) async {
            calls.add('restore:$recoverySecret');
          },
        ),
        throwsA(isA<Exception>()),
      );

      expect(calls, ['connected:invalid recovery secret']);
    });

    test('does not write when validation fails', () async {
      final platform = _FakeBiometricRecoveryKeyPlatform();
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );

      await expectLater(
        store.validateAndSaveForAccountKey(
          accountKey: 'account',
          recoveryKey: 'ABCD EFGH IJKM NPQR STUV WXYZ 1234 5678',
          validator: (_) => throw Exception('invalid'),
        ),
        throwsA(isA<Exception>()),
      );

      expect(platform.writes, isEmpty);
    });

    test('rejects empty or very short recovery secrets before validation',
        () async {
      final platform = _FakeBiometricRecoveryKeyPlatform();
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );
      var validatorCalled = false;

      await expectLater(
        store.validateAndSaveForAccountKey(
          accountKey: 'account',
          recoveryKey: 'too-short',
          validator: (_) async {
            validatorCalled = true;
          },
        ),
        throwsA(isA<BiometricRecoveryKeyStoreException>()),
      );

      expect(validatorCalled, isFalse);
      expect(platform.writes, isEmpty);
    });

    test('reports generic biometric availability failures without writing',
        () async {
      final platform = _FakeBiometricRecoveryKeyPlatform()
        ..status = const BiometricRecoveryKeyStatus(
          supported: true,
          biometricAvailable: false,
          stored: false,
          biometryType: 'fingerprint',
          platform: 'android',
          biometricStrongAvailable: false,
        );
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );
      var validatorCalled = false;

      await expectLater(
        store.validateAndSaveForAccountKey(
          accountKey: 'account',
          recoveryKey: 'ABCD EFGH IJKM NPQR STUV WXYZ 1234 5678',
          validator: (_) async {
            validatorCalled = true;
          },
        ),
        throwsA(
          isA<BiometricRecoveryKeyStoreException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Biometric unlock'),
              isNot(contains('Face ID')),
              isNot(contains('Touch ID')),
            ),
          ),
        ),
      );

      expect(validatorCalled, isFalse);
      expect(platform.writes, isEmpty);
    });

    test('read and delete proxy through native platform', () async {
      final platform = _FakeBiometricRecoveryKeyPlatform()
        ..writes['account'] = 'stored recovery key';

      final value = await platform.readRecoveryKey(
        accountKey: 'account',
        reason: 'test',
      );
      await platform.deleteRecoveryKey(accountKey: 'account');

      expect(value, 'stored recovery key');
      expect(platform.writes, isEmpty);
    });

    test('status and read prefer v2 over legacy v1', () async {
      final platform = _FakeBiometricRecoveryKeyPlatform()
        ..writes['matrix_recovery_key.v2.current'] = 'new recovery key'
        ..writes['matrix_recovery_key.v1.legacy'] = 'old recovery key';
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );

      final status = await store.statusForAccountKeysIncludingLegacy(
        accountKey: 'matrix_recovery_key.v2.current',
        legacyAccountKey: 'matrix_recovery_key.v1.legacy',
      );
      final value = await store.readForAccountKeysIncludingLegacy(
        accountKey: 'matrix_recovery_key.v2.current',
        legacyAccountKey: 'matrix_recovery_key.v1.legacy',
        reason: 'test',
      );

      expect(status.stored, isTrue);
      expect(value, 'new recovery key');
    });

    test('status and read fall back to current-device legacy v1', () async {
      final platform = _FakeBiometricRecoveryKeyPlatform()
        ..writes['matrix_recovery_key.v1.legacy'] = 'old recovery key';
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );

      final status = await store.statusForAccountKeysIncludingLegacy(
        accountKey: 'matrix_recovery_key.v2.current',
        legacyAccountKey: 'matrix_recovery_key.v1.legacy',
      );
      final value = await store.readForAccountKeysIncludingLegacy(
        accountKey: 'matrix_recovery_key.v2.current',
        legacyAccountKey: 'matrix_recovery_key.v1.legacy',
        reason: 'test',
      );

      expect(status.stored, isTrue);
      expect(value, 'old recovery key');
    });

    test('migrates legacy v1 to v2 when keeping the key on logout', () async {
      final platform = _FakeBiometricRecoveryKeyPlatform()
        ..writes['matrix_recovery_key.v1.legacy'] = 'old recovery key';
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );

      await store.ensureAccountScopedCopyForLogoutForAccountKeys(
        accountKey: 'matrix_recovery_key.v2.current',
        legacyAccountKey: 'matrix_recovery_key.v1.legacy',
      );

      expect(
        platform.writes,
        {'matrix_recovery_key.v2.current': 'old recovery key'},
      );
    });

    test('cancelled legacy migration leaves legacy v1 in place', () async {
      final platform = _FakeBiometricRecoveryKeyPlatform()
        ..writes['matrix_recovery_key.v1.legacy'] = 'old recovery key'
        ..readResults['matrix_recovery_key.v1.legacy'] = null;
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );

      await expectLater(
        store.ensureAccountScopedCopyForLogoutForAccountKeys(
          accountKey: 'matrix_recovery_key.v2.current',
          legacyAccountKey: 'matrix_recovery_key.v1.legacy',
        ),
        throwsA(isA<BiometricRecoveryKeyStoreException>()),
      );

      expect(platform.writes, {
        'matrix_recovery_key.v1.legacy': 'old recovery key',
      });
    });

    test('kept current v2 key must be readable before logout', () async {
      final platform = _FakeBiometricRecoveryKeyPlatform()
        ..writes['matrix_recovery_key.v2.current'] = 'new recovery key'
        ..statuses['matrix_recovery_key.v2.current'] =
            const BiometricRecoveryKeyStatus(
          supported: true,
          biometricAvailable: false,
          stored: true,
          biometryType: 'fingerprint',
          unavailableReason: 'biometry_changed_or_unavailable',
        );
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );

      await expectLater(
        store.ensureAccountScopedCopyForLogoutForAccountKeys(
          accountKey: 'matrix_recovery_key.v2.current',
          legacyAccountKey: 'matrix_recovery_key.v1.legacy',
        ),
        throwsA(
          isA<BiometricRecoveryKeyStoreException>().having(
            (error) => error.message,
            'message',
            contains('cannot be unlocked'),
          ),
        ),
      );

      expect(platform.writes, {
        'matrix_recovery_key.v2.current': 'new recovery key',
      });
    });

    test('delete removes both v2 and current-device legacy v1', () async {
      final platform = _FakeBiometricRecoveryKeyPlatform()
        ..writes['matrix_recovery_key.v2.current'] = 'new recovery key'
        ..writes['matrix_recovery_key.v1.legacy'] = 'old recovery key';
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );

      await store.deleteForAccountKeysIncludingLegacy(
        accountKey: 'matrix_recovery_key.v2.current',
        legacyAccountKey: 'matrix_recovery_key.v1.legacy',
      );

      expect(platform.writes, isEmpty);
    });

    test('delete all local recovery keys clears every platform record',
        () async {
      final platform = _FakeBiometricRecoveryKeyPlatform()
        ..writes['matrix_recovery_key.v2.current'] = 'new recovery key'
        ..writes['matrix_recovery_key.v1.legacy'] = 'old recovery key'
        ..writes['matrix_recovery_key.v1.orphaned'] = 'orphaned recovery key';
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: true,
      );

      await store.deleteAllLocalRecoveryKeys();

      expect(platform.deleteAllCalls, 1);
      expect(platform.writes, isEmpty);
    });

    test('delete all local recovery keys skips unsupported platforms',
        () async {
      final platform = _FakeBiometricRecoveryKeyPlatform()
        ..writes['matrix_recovery_key.v2.current'] = 'new recovery key';
      final store = BiometricRecoveryKeyStore(
        platform: platform,
        isSupportedPlatformOverride: false,
      );

      await store.deleteAllLocalRecoveryKeys();

      expect(platform.deleteAllCalls, 0);
      expect(platform.writes, {
        'matrix_recovery_key.v2.current': 'new recovery key',
      });
    });

    test('logout flow keeps key before normal logout', () async {
      final calls = <String>[];

      final completed = await BiometricRecoveryKeyLogoutFlow.run(
        choice: BiometricRecoveryKeyLogoutChoice.keep,
        ensureKeyPrepared: () async => calls.add('keep'),
        deleteKey: () async => calls.add('delete'),
        logout: () async => calls.add('logout'),
      );

      expect(completed, isTrue);
      expect(calls, ['keep', 'logout']);
    });

    test('logout flow deletes key before normal logout', () async {
      final calls = <String>[];

      final completed = await BiometricRecoveryKeyLogoutFlow.run(
        choice: BiometricRecoveryKeyLogoutChoice.delete,
        ensureKeyPrepared: () async => calls.add('keep'),
        deleteKey: () async => calls.add('delete'),
        logout: () async => calls.add('logout'),
      );

      expect(completed, isTrue);
      expect(calls, ['delete', 'logout']);
    });

    test('logout flow with status skips prompt when no key is stored',
        () async {
      final calls = <String>[];

      final completed = await BiometricRecoveryKeyLogoutFlow.runForStatus(
        status: const BiometricRecoveryKeyStatus(
          supported: true,
          biometricAvailable: true,
          stored: false,
          biometryType: 'face_id',
        ),
        requestChoice: (_) async {
          calls.add('prompt');
          return BiometricRecoveryKeyLogoutChoice.keep;
        },
        ensureKeyPrepared: () async => calls.add('keep'),
        deleteKey: () async => calls.add('delete'),
        logout: () async => calls.add('logout'),
      );

      expect(completed, isTrue);
      expect(calls, ['logout']);
    });

    test('logout flow with status asks before keeping stored key', () async {
      final calls = <String>[];

      final completed = await BiometricRecoveryKeyLogoutFlow.runForStatus(
        status: const BiometricRecoveryKeyStatus(
          supported: true,
          biometricAvailable: true,
          stored: true,
          biometryType: 'fingerprint',
        ),
        requestChoice: (status) async {
          calls.add('prompt:${status.promptLabel}');
          return BiometricRecoveryKeyLogoutChoice.keep;
        },
        ensureKeyPrepared: () async => calls.add('keep'),
        deleteKey: () async => calls.add('delete'),
        logout: () async => calls.add('logout'),
      );

      expect(completed, isTrue);
      expect(calls, ['prompt:Fingerprint', 'keep', 'logout']);
    });

    test('logout flow with status rejects keeping an unreadable stored key',
        () async {
      final calls = <String>[];
      Object? capturedError;

      final completed = await BiometricRecoveryKeyLogoutFlow.runForStatus(
        status: const BiometricRecoveryKeyStatus(
          supported: true,
          biometricAvailable: false,
          stored: true,
          biometryType: 'fingerprint',
          unavailableReason: 'biometry_changed_or_unavailable',
        ),
        requestChoice: (status) async {
          calls.add('prompt:${status.promptLabel}');
          return BiometricRecoveryKeyLogoutChoice.keep;
        },
        ensureKeyPrepared: () async => calls.add('keep'),
        deleteKey: () async => calls.add('delete'),
        logout: () async => calls.add('logout'),
        onStorageFailure: (choice, error, stackTrace) {
          calls.add('failure:$choice');
          capturedError = error;
        },
      );

      expect(completed, isFalse);
      expect(calls, [
        'prompt:Fingerprint',
        'failure:BiometricRecoveryKeyLogoutChoice.keep',
      ]);
      expect(capturedError, isA<BiometricRecoveryKeyStoreException>());
    });

    test('logout flow with status cancel aborts stored-key logout', () async {
      final calls = <String>[];

      final completed = await BiometricRecoveryKeyLogoutFlow.runForStatus(
        status: const BiometricRecoveryKeyStatus(
          supported: true,
          biometricAvailable: true,
          stored: true,
          biometryType: 'face_id',
        ),
        requestChoice: (_) async {
          calls.add('prompt');
          return BiometricRecoveryKeyLogoutChoice.cancel;
        },
        ensureKeyPrepared: () async => calls.add('keep'),
        deleteKey: () async => calls.add('delete'),
        logout: () async => calls.add('logout'),
      );

      expect(completed, isFalse);
      expect(calls, ['prompt']);
    });

    test('logout flow with status reports storage failure and skips logout',
        () async {
      final calls = <String>[];
      Object? capturedError;

      final completed = await BiometricRecoveryKeyLogoutFlow.runForStatus(
        status: const BiometricRecoveryKeyStatus(
          supported: true,
          biometricAvailable: true,
          stored: true,
          biometryType: 'face_id',
        ),
        requestChoice: (_) async => BiometricRecoveryKeyLogoutChoice.keep,
        ensureKeyPrepared: () async {
          calls.add('keep');
          throw StateError('cancelled');
        },
        deleteKey: () async => calls.add('delete'),
        logout: () async => calls.add('logout'),
        onStorageFailure: (choice, error, stackTrace) {
          calls.add('failure:$choice');
          capturedError = error;
        },
      );

      expect(completed, isFalse);
      expect(calls, ['keep', 'failure:BiometricRecoveryKeyLogoutChoice.keep']);
      expect(capturedError, isA<StateError>());
    });

    test('logout flow cancel skips storage changes and logout', () async {
      final calls = <String>[];

      final completed = await BiometricRecoveryKeyLogoutFlow.run(
        choice: BiometricRecoveryKeyLogoutChoice.cancel,
        ensureKeyPrepared: () async => calls.add('keep'),
        deleteKey: () async => calls.add('delete'),
        logout: () async => calls.add('logout'),
      );

      expect(completed, isFalse);
      expect(calls, isEmpty);
    });

    test('logout flow aborts normal logout when keep preparation fails',
        () async {
      final calls = <String>[];

      await expectLater(
        BiometricRecoveryKeyLogoutFlow.run(
          choice: BiometricRecoveryKeyLogoutChoice.keep,
          ensureKeyPrepared: () async {
            calls.add('keep');
            throw StateError('cancelled');
          },
          deleteKey: () async => calls.add('delete'),
          logout: () async => calls.add('logout'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(calls, ['keep']);
    });

    test('logout flow aborts normal logout when delete fails', () async {
      final calls = <String>[];

      await expectLater(
        BiometricRecoveryKeyLogoutFlow.run(
          choice: BiometricRecoveryKeyLogoutChoice.delete,
          ensureKeyPrepared: () async => calls.add('keep'),
          deleteKey: () async {
            calls.add('delete');
            throw StateError('delete failed');
          },
          logout: () async => calls.add('logout'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(calls, ['delete']);
    });

    test('method channel read maps native unavailable errors to no key',
        () async {
      const channel = MethodChannel('test.secure_recovery_key');
      final platform = MethodChannelBiometricRecoveryKeyPlatform(
        channel: channel,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
      });

      for (final code in [
        'not_found',
        'auth_cancelled',
        'auth_failed',
        'biometry_changed_or_unavailable',
        'biometrics_unavailable',
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: code);
        });

        final value = await platform.readRecoveryKey(
          accountKey: 'account',
          reason: 'test',
        );

        expect(value, isNull, reason: code);
      }
    });

    test('method channel write maps missing plugin to unavailable error',
        () async {
      const channel = MethodChannel('test.missing_secure_recovery_key');
      final platform = MethodChannelBiometricRecoveryKeyPlatform(
        channel: channel,
      );

      await expectLater(
        platform.writeRecoveryKey(
          accountKey: 'account',
          recoveryKey: 'ABCD EFGH IJKM NPQR STUV WXYZ 1234 5678',
        ),
        throwsA(
          isA<BiometricRecoveryKeyStoreException>().having(
            (error) => error.message,
            'message',
            contains('not available'),
          ),
        ),
      );
    });

    test('method channel delete all invokes native cleanup without account key',
        () async {
      const channel = MethodChannel('test.secure_recovery_key.delete_all');
      final platform = MethodChannelBiometricRecoveryKeyPlatform(
        channel: channel,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
      });
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });

      await platform.deleteAllRecoveryKeys();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'deleteAllRecoveryKeys');
      expect(calls.single.arguments, isNull);
    });

    test('method channel delete all ignores missing plugin', () async {
      const channel = MethodChannel(
        'test.missing_secure_recovery_key.delete_all',
      );
      final platform = MethodChannelBiometricRecoveryKeyPlatform(
        channel: channel,
      );

      await platform.deleteAllRecoveryKeys();
    });
  });
}

class _FakeBiometricRecoveryKeyPlatform
    implements BiometricRecoveryKeyNativePlatform {
  final writes = <String, String>{};
  final readResults = <String, String?>{};
  final statuses = <String, BiometricRecoveryKeyStatus>{};
  BiometricRecoveryKeyStatus? status;
  var statusCalls = 0;
  var deleteAllCalls = 0;

  @override
  Future<void> deleteRecoveryKey({required String accountKey}) async {
    writes.remove(accountKey);
  }

  @override
  Future<void> deleteAllRecoveryKeys() async {
    deleteAllCalls += 1;
    writes.clear();
    readResults.clear();
    statuses.clear();
  }

  @override
  Future<BiometricRecoveryKeyStatus> getStatus({
    required String accountKey,
  }) async {
    statusCalls += 1;
    final accountStatus = statuses[accountKey];
    if (accountStatus != null) {
      return accountStatus;
    }
    return status ??
        BiometricRecoveryKeyStatus(
          supported: true,
          biometricAvailable: true,
          stored: writes.containsKey(accountKey),
          biometryType: 'face_id',
        );
  }

  @override
  Future<String?> readRecoveryKey({
    required String accountKey,
    required String reason,
  }) async {
    if (readResults.containsKey(accountKey)) {
      return readResults[accountKey];
    }
    return writes[accountKey];
  }

  @override
  Future<void> writeRecoveryKey({
    required String accountKey,
    required String recoveryKey,
  }) async {
    writes[accountKey] = recoveryKey;
  }
}
