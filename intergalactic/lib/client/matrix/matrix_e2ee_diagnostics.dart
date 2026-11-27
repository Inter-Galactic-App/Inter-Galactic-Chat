import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:intergalactic/client/matrix/matrix_bad_encrypted_recovery.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/debug/matrix_decrypt_log_summarizer.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix_api_lite.dart' as matrix_api;

enum MatrixE2eeBackupProbeOutcome { inBackup, notInBackup, versionUnusable }

class MatrixE2eeBackupProbeSummary {
  const MatrixE2eeBackupProbeSummary({
    required this.candidates,
    required this.inBackup,
    required this.notInBackup,
    required this.versionUnusable,
    required this.skippedBudget,
  });

  final int candidates;
  final int inBackup;
  final int notInBackup;
  final int versionUnusable;
  final int skippedBudget;
}

/// A developer-only, host-side measurement window for E10.
///
/// It deliberately owns no key material. The callback only reports whether a
/// server-side backup lookup succeeded, missed, or could not be evaluated.
/// The window is opened around the wake's existing sync, so its work is
/// bounded by the same budget instead of becoming a second wake phase.
class MatrixE2eeBackupProbeScope {
  MatrixE2eeBackupProbeScope({
    required this.enabled,
    required Duration budget,
    this.routeClientId,
    this.routeRoomId,
    this.routeEventId,
    DateTime Function()? now,
  }) : _deadline = (now ?? DateTime.now).call().add(budget),
       _now = now ?? DateTime.now;

  static const Duration probeTimeout = Duration(milliseconds: 750);
  static const int maxProbes = 2;

  final bool enabled;
  final String? routeClientId;
  final String? routeRoomId;
  final String? routeEventId;
  final DateTime _deadline;
  final DateTime Function() _now;
  final List<Future<void>> _inFlight = <Future<void>>[];
  int _started = 0;
  int _candidates = 0;
  int _inBackup = 0;
  int _notInBackup = 0;
  int _versionUnusable = 0;
  int _skippedBudget = 0;
  bool _finished = false;

  Future<void> record(
    Future<MatrixE2eeBackupProbeOutcome> Function(Duration timeout) probe,
  ) {
    if (!enabled || _finished) {
      return Future<void>.value();
    }
    _candidates++;

    final remaining = _deadline.difference(_now());
    if (_started >= maxProbes || remaining <= probeTimeout) {
      _skippedBudget++;
      return Future<void>.value();
    }

    _started++;
    final timeout = remaining < probeTimeout ? remaining : probeTimeout;
    late final Future<void> inFlight;
    inFlight = () async {
      MatrixE2eeBackupProbeOutcome outcome;
      try {
        outcome = await probe(timeout);
      } catch (_) {
        outcome = MatrixE2eeBackupProbeOutcome.versionUnusable;
      }
      switch (outcome) {
        case MatrixE2eeBackupProbeOutcome.inBackup:
          _inBackup++;
        case MatrixE2eeBackupProbeOutcome.notInBackup:
          _notInBackup++;
        case MatrixE2eeBackupProbeOutcome.versionUnusable:
          _versionUnusable++;
      }
    }();
    _inFlight.add(inFlight);
    return inFlight.whenComplete(() => _inFlight.remove(inFlight));
  }

  /// Records a candidate only when it is the exact APNs-routed event for the
  /// routed client. The active scope is process-global while all clients sync,
  /// so this guard prevents an unrelated account's decrypt failure from
  /// changing this wake's developer-only aggregate.
  Future<void> recordForRoute({
    required String clientId,
    required String roomId,
    required String eventId,
    required Future<MatrixE2eeBackupProbeOutcome> Function(Duration timeout)
    probe,
  }) {
    if (clientId != routeClientId ||
        roomId != routeRoomId ||
        eventId != routeEventId) {
      return Future<void>.value();
    }
    return record(probe);
  }

  Future<MatrixE2eeBackupProbeSummary> finish() async {
    _finished = true;
    await Future.wait(List<Future<void>>.of(_inFlight));
    return MatrixE2eeBackupProbeSummary(
      candidates: _candidates,
      inBackup: _inBackup,
      notInBackup: _notInBackup,
      versionUnusable: _versionUnusable,
      skippedBudget: _skippedBudget,
    );
  }
}

class MatrixE2eeDiagnostics {
  MatrixE2eeDiagnostics({
    required matrix.Client client,
    required String clientId,
    bool suppressAutomaticRepair = false,
    Future<void> Function()? onPersistentRequestableSessionFailure,
    Future<void> Function()? onRequestableRoomKeyReceived,
  }) : _client = client,
       _clientId = clientId,
       _suppressAutomaticRepair = suppressAutomaticRepair,
       _onPersistentRequestableSessionFailure =
           onPersistentRequestableSessionFailure,
       _onRequestableRoomKeyReceived = onRequestableRoomKeyReceived,
       _missingRoomSessionStalenessTracker =
           MatrixMissingRoomSessionStalenessTracker(hash: _hash) {
    _persistentRequestableSessionRepairDispatcher =
        MatrixPersistentRequestableSessionRepairDispatcher(
          isDisposed: () => _disposed,
          callback: _onPersistentRequestableSessionFailure,
          onFailure: (error, trace) {
            Log.onError(
              error,
              trace,
              content:
                  'Automatic Matrix E2EE key-delivery repair did not complete',
              category: LogCategory.matrix,
              source: 'matrix-e2ee',
            );
          },
        );
    _receivedRequestableRoomKeyRetryDispatcher =
        MatrixPersistentRequestableSessionRepairDispatcher(
          isDisposed: () => _disposed,
          callback: _onRequestableRoomKeyReceived,
          onFailure: (error, trace) {
            Log.onError(
              error,
              trace,
              content: 'Retry after late Matrix E2EE room key did not complete',
              category: LogCategory.matrix,
              source: 'matrix-e2ee',
            );
          },
        );
    _lateRoomKeyRetryCoordinator = MatrixLateRoomKeyRetryCoordinator(
      tracker: _missingRoomSessionStalenessTracker,
      dispatcher: _receivedRequestableRoomKeyRetryDispatcher,
      suppressAutomaticRepair: _suppressAutomaticRepair,
    );
  }

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
  static const Duration _timelineDecryptFailureLogInterval = Duration(
    seconds: 30,
  );

  static bool _sdkLogBridgeInstalled = false;
  static final MatrixDecryptLogSummarizer _sdkRoomDecryptLogSummarizer =
      MatrixDecryptLogSummarizer(sourceLabel: 'sdk-log');
  static DateTime? _lastIgnoredCallMemberLogAt;
  static int _ignoredCallMemberLogCount = 0;
  static MatrixE2eeBackupProbeScope? _activeBackupProbeScope;

  static MatrixE2eeBackupProbeScope? get activeBackupProbeScope =>
      _activeBackupProbeScope;

  static Future<T> withBackupProbeScope<T>(
    MatrixE2eeBackupProbeScope scope,
    Future<T> Function() action,
  ) async {
    final previous = _activeBackupProbeScope;
    _activeBackupProbeScope = scope;
    try {
      return await action();
    } finally {
      _activeBackupProbeScope = previous;
    }
  }

  final matrix.Client _client;
  final String _clientId;
  final bool _suppressAutomaticRepair;
  final Future<void> Function()? _onPersistentRequestableSessionFailure;
  final Future<void> Function()? _onRequestableRoomKeyReceived;
  final MatrixMissingRoomSessionStalenessTracker
  _missingRoomSessionStalenessTracker;
  final Map<String, DateTime> _lastTimelineRequestLog = <String, DateTime>{};
  final Map<String, _TimelineDecryptFailureBucket>
  _timelineDecryptFailureBuckets = <String, _TimelineDecryptFailureBucket>{};

  StreamSubscription<matrix.Event>? _timelineSubscription;
  StreamSubscription<matrix.Event>? _historySubscription;
  StreamSubscription<matrix.ToDeviceEvent>? _toDeviceSubscription;
  StreamSubscription<matrix.SdkError>? _encryptionErrorSubscription;
  StreamSubscription<String>? _keySharingPolicySubscription;
  Future<void>? _olmRepairInFlight;
  bool _olmRepairInFlightIncludesSync = false;
  DateTime? _lastOlmRepairAt;
  bool _lastOlmRepairIncludedSync = false;
  late final MatrixPersistentRequestableSessionRepairDispatcher
  _persistentRequestableSessionRepairDispatcher;
  late final MatrixPersistentRequestableSessionRepairDispatcher
  _receivedRequestableRoomKeyRetryDispatcher;
  late final MatrixLateRoomKeyRetryCoordinator _lateRoomKeyRetryCoordinator;

  /// Set by [dispose] and never cleared: this object is created once per
  /// client and disposed once, from `MatrixClient.close()`.
  ///
  /// The automatic repair below is started with `unawaited` and then awaits
  /// several network stages, so logout or client close can land in the middle
  /// of one. Close does not wait for the repair (that would block teardown for
  /// the length of a bounded sync); the repair checks this flag at every stage
  /// boundary and abandons itself instead.
  bool _disposed = false;
  bool? _cryptoIdentityInitialized;
  bool? _cryptoIdentityConnected;
  bool? _keyBackupCached;
  bool? _crossSigningCached;

  void start() {
    installSdkLogBridge();
    applyConfiguredShareKeysWith();
    _keySharingPolicySubscription ??= preferences
        .matrixKeySharingPolicy
        .onChanged
        .listen((_) => applyConfiguredShareKeysWith());
    _timelineSubscription ??= _client.onTimelineEvent.stream.listen(
      _recordTimelineEvent,
    );
    _historySubscription ??= _client.onHistoryEvent.stream.listen(
      (event) => _recordTimelineEvent(event, source: 'history'),
    );
    _toDeviceSubscription ??= _client.onToDeviceEvent.stream.listen(
      _recordToDeviceEvent,
    );
    _encryptionErrorSubscription ??= _client.onEncryptionError.stream.listen(
      _recordEncryptionError,
    );
  }

  /// Developer-mode reproduction seam for the persistent requestable-session
  /// repair. It invokes the same bounded automatic callback after the normal
  /// tracker would have become stale; it never creates an event, removes a
  /// session, or changes key-sharing policy.
  Future<bool> runDeveloperPersistentRequestableSessionRepair() async {
    final dispatched = await _persistentRequestableSessionRepairDispatcher
        .dispatchForDeveloper(
          developerModeEnabled: preferences.developerMode.value,
          suppressAutomaticRepair: _suppressAutomaticRepair,
        );
    if (dispatched) {
      Log.i(
        'Developer simulated persistent requestable-session E2EE repair',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    }
    return dispatched;
  }

  Future<void> dispose() async {
    _disposed = true;
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
    final ownKeys = userId == null
        ? null
        : _client.userDeviceKeys[userId]?.deviceKeys;
    final ownDevices = ownKeys?.values.toList() ?? <matrix.DeviceKeys>[];
    final currentDeviceKeys = deviceId == null ? null : ownKeys?[deviceId];
    final masterKey = userId == null
        ? null
        : _client.userDeviceKeys[userId]?.masterKey;

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
      verifiedOwnDeviceCount: ownDevices
          .where((device) => device.verified)
          .length,
      blockedOwnDeviceCount: ownDevices
          .where((device) => device.blocked)
          .length,
      encryptableOwnDeviceCount: ownDevices
          .where((device) => device.encryptToDevice)
          .length,
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

  Future<void> _refreshRecoveryState({required String reason}) async {
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
      final keyBackupCached = await encryption.keyManager.isCached().timeout(
        const Duration(seconds: 8),
      );
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
    if (_disposed) {
      return;
    }

    // Throttling is tracked per *sync capability*, not per repair. A repair
    // that skipped the bounded sync does not satisfy a caller that asked for
    // one: the encryption-error path starts includeSync: false repairs, and
    // the persistent-room-key callback that follows relies on the sync to
    // actually fetch the missing room key before it retries decryption.
    // Suppressing that request against a sync-less repair silently dropped the
    // one step it depends on. Equivalent sync-capable repairs still throttle.
    final runningRepair = _olmRepairInFlight;
    if (runningRepair != null) {
      final runningIncludedSync = _olmRepairInFlightIncludesSync;
      Log.i(
        'Waiting for existing Matrix E2EE repair before starting reason=$reason',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
      await runningRepair;
      if (!includeSync || runningIncludedSync || _disposed) {
        return;
      }
      Log.i(
        'Upgrading Matrix E2EE repair reason=$reason because the repair it '
        'waited on did not include a sync',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    } else if (!force && _repairThrottled(includeSync: includeSync)) {
      Log.w(
        'Skipping Matrix E2EE repair reason=$reason because one ran recently',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
      return;
    }

    final now = DateTime.now();
    final repair = _runOlmToDeviceRepair(
      reason: reason,
      includeSync: includeSync,
    );
    _olmRepairInFlight = repair;
    _olmRepairInFlightIncludesSync = includeSync;
    _lastOlmRepairAt = now;
    _lastOlmRepairIncludedSync = includeSync;
    try {
      await repair;
    } finally {
      if (identical(_olmRepairInFlight, repair)) {
        _olmRepairInFlight = null;
        _olmRepairInFlightIncludesSync = false;
      }
    }
  }

  Future<void> _runOlmToDeviceRepair({
    required String reason,
    required bool includeSync,
  }) async {
    final encryption = _client.encryption;
    if (_disposed ||
        !_client.encryptionEnabled ||
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

    if (!_repairContextStillValid) {
      _logRepairAbandoned(reason, stage: 'ssss_cache');
      return;
    }

    try {
      await encryption.ssss.periodicallyRequestMissingCache().timeout(
        const Duration(seconds: 8),
      );
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Matrix E2EE repair could not refresh SSSS cache',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    }

    if (!_repairContextStillValid) {
      _logRepairAbandoned(reason, stage: 'recovery_state');
      return;
    }

    await _refreshRecoveryState(reason: 'repair_$reason');

    if (!includeSync) {
      return;
    }

    if (!_repairContextStillValid) {
      _logRepairAbandoned(reason, stage: 'bounded_sync');
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

  /// Whether a recent repair suppresses this request.
  ///
  /// A sync-capable request is only suppressed by a repair that itself
  /// included the bounded sync - see [repairOlmToDevicePath].
  bool _repairThrottled({required bool includeSync}) {
    final lastAt = _lastOlmRepairAt;
    if (lastAt == null) {
      return false;
    }
    if (includeSync && !_lastOlmRepairIncludedSync) {
      return false;
    }
    return DateTime.now().difference(lastAt) < const Duration(minutes: 5);
  }

  /// Whether the repair may still touch the SDK or the network.
  ///
  /// Re-checked at every stage boundary rather than only on entry: the repair
  /// is detached and each stage awaits a timeout-bounded network call, so a
  /// logout or `MatrixClient.close()` can land between two of them.
  bool get _repairContextStillValid => !_disposed && _client.isLogged();

  void _logRepairAbandoned(String reason, {required String stage}) {
    Log.w(
      'Abandoning Matrix E2EE repair reason=$reason stage=$stage because the '
      'client was closed or logged out',
      category: LogCategory.matrix,
      source: 'matrix-e2ee',
    );
  }

  void _recordTimelineEvent(matrix.Event event, {String source = 'timeline'}) {
    if (event.type != matrix.EventTypes.Encrypted ||
        event.messageType != matrix.MessageTypes.BadEncrypted) {
      return;
    }

    final canRequestSession =
        matrixBadEncryptedEventHasStructuredSessionRequestSignal(event);
    final reason = _classifyErrorText(event.content['body']?.toString());
    _recordTimelineDecryptFailureSummary(
      event,
      source: source,
      reason: reason,
      canRequestSession: canRequestSession,
    );

    final sessionId = _stringValue(event.content['session_id']);
    final backupProbeScope = activeBackupProbeScope;
    if (sessionId != null && backupProbeScope != null) {
      unawaited(
        backupProbeScope.recordForRoute(
          clientId: _clientId,
          roomId: event.room.id,
          eventId: event.eventId,
          probe: (timeout) => _probeServerBackupPresence(
            client: _client,
            roomId: event.room.id,
            sessionId: sessionId,
            timeout: timeout,
          ),
        ),
      );
    }

    if (canRequestSession) {
      _recordRequestableSessionKey(event, source: source);
    }
  }

  /// Reads the pushed encrypted event without decrypting it, then probes only
  /// the server-side backup presence of its Megolm session. This closes the
  /// gap where the wake receives the room key before the host emits a
  /// [matrix.MessageTypes.BadEncrypted] timeline event.
  static Future<MatrixE2eeBackupProbeOutcome> probePushedEncryptedEvent({
    required matrix.Client client,
    required String roomId,
    required String eventId,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Duration remaining() => deadline.difference(DateTime.now());

    try {
      final event = await client
          .getOneRoomEvent(roomId, eventId)
          .timeout(remaining());
      if (event.type != matrix.EventTypes.Encrypted) {
        return MatrixE2eeBackupProbeOutcome.versionUnusable;
      }
      final sessionId = _stringValue(event.content['session_id']);
      if (sessionId == null) {
        return MatrixE2eeBackupProbeOutcome.versionUnusable;
      }
      final budget = remaining();
      if (budget <= Duration.zero) {
        return MatrixE2eeBackupProbeOutcome.versionUnusable;
      }
      return _probeServerBackupPresence(
        client: client,
        roomId: roomId,
        sessionId: sessionId,
        timeout: budget,
      );
    } catch (_) {
      return MatrixE2eeBackupProbeOutcome.versionUnusable;
    }
  }

  static Future<MatrixE2eeBackupProbeOutcome> _probeServerBackupPresence({
    required matrix.Client client,
    required String roomId,
    required String sessionId,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Duration remaining() => deadline.difference(DateTime.now());

    matrix_api.GetRoomKeysVersionCurrentResponse version;
    try {
      final versionResponse = await client.getRoomKeysVersionCurrent().timeout(
        remaining(),
      );
      if (versionResponse.version.isEmpty) {
        return MatrixE2eeBackupProbeOutcome.versionUnusable;
      }
      version = versionResponse;
    } on matrix.MatrixException {
      // A version-level 403/404 is deliberately not a negative key lookup:
      // the backup cannot be evaluated when its version is unavailable.
      return MatrixE2eeBackupProbeOutcome.versionUnusable;
    } catch (_) {
      return MatrixE2eeBackupProbeOutcome.versionUnusable;
    }

    if (version.algorithm !=
        matrix_api.BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2) {
      return MatrixE2eeBackupProbeOutcome.versionUnusable;
    }

    try {
      await client
          .getRoomKeyBySessionId(roomId, sessionId, version.version)
          .timeout(remaining());
      return MatrixE2eeBackupProbeOutcome.inBackup;
    } on matrix.MatrixException catch (error) {
      if (error.response?.statusCode == 404) {
        return MatrixE2eeBackupProbeOutcome.notInBackup;
      }
      return MatrixE2eeBackupProbeOutcome.versionUnusable;
    } catch (_) {
      return MatrixE2eeBackupProbeOutcome.versionUnusable;
    }
  }

  void _recordTimelineDecryptFailureSummary(
    matrix.Event event, {
    required String source,
    required String reason,
    required bool canRequestSession,
  }) {
    final key = '$source|$reason|$canRequestSession';
    final bucket = _timelineDecryptFailureBuckets.putIfAbsent(
      key,
      () => _TimelineDecryptFailureBucket(),
    );
    bucket.add(
      roomHash: _hash(event.room.id),
      eventHash: _hash(event.eventId),
      senderHash: _hash(event.senderId),
      sessionHash: _hash(_stringValue(event.content['session_id'])),
      senderKeyHash: _hash(_stringValue(event.content['sender_key'])),
    );

    final now = DateTime.now();
    final lastLoggedAt = bucket.lastLoggedAt;
    if (lastLoggedAt != null &&
        now.difference(lastLoggedAt) < _timelineDecryptFailureLogInterval) {
      return;
    }

    Log.w(
      'E2EE decrypt failures summarized source=$source '
      'client=${_hash(_clientId)} reason=$reason '
      'can_request_session=$canRequestSession count=${bucket.count} '
      'rooms=${bucket.roomsLabel} senders=${bucket.sendersLabel} '
      'sessions=${bucket.sessionsLabel} sender_keys=${bucket.senderKeysLabel} '
      'first_event=${bucket.firstEventHash} latest_event=${bucket.latestEventHash}',
      category: LogCategory.matrix,
      source: 'matrix-e2ee',
    );
    bucket.resetAfterLog(now);
  }

  void _recordRequestableSessionKey(
    matrix.Event event, {
    required String source,
  }) {
    _logRequestableSessionKey(event, source: source);

    final staleSummary = _missingRoomSessionStalenessTracker.recordMissing(
      source: source,
      roomId: event.room.id,
      senderId: event.senderId,
      sessionId: _stringValue(event.content['session_id']),
      senderKey: _stringValue(event.content['sender_key']),
    );
    if (staleSummary == null) {
      return;
    }

    Log.w(
      'E2EE missing room session still unresolved '
      'sources=${staleSummary.sourcesLabel} '
      'room=${staleSummary.roomHash} '
      'sender=${staleSummary.senderHash} '
      'session=${staleSummary.sessionHash} '
      'sender_key=${staleSummary.senderKeyHash} '
      'observations=${staleSummary.observations} '
      'age_s=${staleSummary.ageSeconds}',
      category: LogCategory.matrix,
      source: 'matrix-e2ee',
    );

    if (_disposed ||
        _suppressAutomaticRepair ||
        !_persistentRequestableSessionRepairDispatcher.hasCallback) {
      return;
    }

    Log.w(
      'Starting bounded Matrix E2EE key-delivery repair after persistent '
      'requestable missing room session',
      category: LogCategory.matrix,
      source: 'matrix-e2ee',
    );
    unawaited(
      _persistentRequestableSessionRepairDispatcher.dispatch(
        suppressAutomaticRepair: _suppressAutomaticRepair,
      ),
    );
  }

  void _logRequestableSessionKey(matrix.Event event, {required String source}) {
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
        final roomId = _stringValue(event.content['room_id']);
        final sessionId = _stringValue(event.content['session_id']);
        Log.i(
          'E2EE to-device key received type=${event.type} '
          'sender=${_hash(event.sender)} '
          'room=${_hash(roomId)} '
          'session=${_hash(sessionId)} '
          'encrypted=${event.encryptedContent != null}',
          category: LogCategory.matrix,
          source: 'matrix-e2ee',
        );
        final resolvedSummary = _lateRoomKeyRetryCoordinator
            .recordRoomKeyReceived(roomId: roomId, sessionId: sessionId);
        if (resolvedSummary != null) {
          Log.i(
            'E2EE requestable missing room session resolved '
            'room=${resolvedSummary.roomHash} '
            'session=${resolvedSummary.sessionHash} '
            'senders=${resolvedSummary.sendersLabel} '
            'observations=${resolvedSummary.observations} '
            'age_s=${resolvedSummary.ageSeconds}',
            category: LogCategory.matrix,
            source: 'matrix-e2ee',
          );
          // The key arrived after a decrypt failure. It is now available to the
          // SDK, but the failed timeline event will not retry by itself.
        }
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

    final repairable =
        reason == 'unknown_one_time_key' ||
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

  static void installSdkLogBridge() {
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

    final handledRoomDecryptLog = _sdkRoomDecryptLogSummarizer.record(
      '$title ${formattedException ?? ''}',
      emit: (message) =>
          Log.i(message, category: LogCategory.matrix, source: 'matrix-sdk'),
    );
    if (handledRoomDecryptLog) {
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
    return lower.contains(
          'ignoring call event org.matrix.msc3401.call.member',
        ) &&
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
    if (lower.contains('reason=unknown_one_time_key') ||
        lower.contains('unknown one-time key')) {
      return 'unknown_one_time_key';
    }
    if (lower.contains('reason=missing_room_session') ||
        lower.contains('has not sent us a session key') ||
        lower.contains('has not sent us the session key') ||
        lower.contains('unknown inbound group session') ||
        lower.contains('unknown session')) {
      return 'missing_room_session';
    }
    if (lower.contains('reason=unverified_or_withheld') ||
        lower.contains('m.unverified') ||
        lower.contains('unverified device') ||
        lower.contains('not verified')) {
      return 'unverified_or_withheld';
    }
    if (lower.contains('reason=unable_to_decrypt_olm') ||
        lower.contains('unabletodecryptwithanyolmsession') ||
        lower.contains('unable to decrypt with any olm session')) {
      return 'unable_to_decrypt_olm';
    }
    if (lower.contains('reason=olm_decryption_failed') ||
        lower.contains('decryption failed')) {
      return 'olm_decryption_failed';
    }
    if (lower.contains('reason=corrupted_session') ||
        matrixBadEncryptedBodyMentionsRequestableSessionFailure(text)) {
      return 'corrupted_session';
    }
    if (lower.contains('reason=not_sent_for_this_device') ||
        lower.contains('is not sent for this device')) {
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
    final cleaned = Log.redactSensitiveInfo(
      value,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
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

class _TimelineDecryptFailureBucket {
  static const int _sampleLimit = 4;

  DateTime? lastLoggedAt;
  int count = 0;
  String? firstEventHash;
  String latestEventHash = 'none';
  final Set<String> _roomHashes = <String>{};
  final Set<String> _senderHashes = <String>{};
  final Set<String> _sessionHashes = <String>{};
  final Set<String> _senderKeyHashes = <String>{};

  void add({
    required String roomHash,
    required String eventHash,
    required String senderHash,
    required String sessionHash,
    required String senderKeyHash,
  }) {
    count++;
    firstEventHash ??= eventHash;
    latestEventHash = eventHash;
    _addSample(_roomHashes, roomHash);
    _addSample(_senderHashes, senderHash);
    _addSample(_sessionHashes, sessionHash);
    _addSample(_senderKeyHashes, senderKeyHash);
  }

  String get roomsLabel => _label(_roomHashes);
  String get sendersLabel => _label(_senderHashes);
  String get sessionsLabel => _label(_sessionHashes);
  String get senderKeysLabel => _label(_senderKeyHashes);

  void resetAfterLog(DateTime loggedAt) {
    lastLoggedAt = loggedAt;
    count = 0;
    firstEventHash = null;
    latestEventHash = 'none';
    _roomHashes.clear();
    _senderHashes.clear();
    _sessionHashes.clear();
    _senderKeyHashes.clear();
  }

  static void _addSample(Set<String> values, String value) {
    if (values.length < _sampleLimit || values.contains(value)) {
      values.add(value);
    }
  }

  static String _label(Set<String> values) {
    if (values.isEmpty) {
      return 'none';
    }
    return values.join(',');
  }
}

class MatrixPersistentRequestableSessionRepairDispatcher {
  MatrixPersistentRequestableSessionRepairDispatcher({
    required bool Function() isDisposed,
    Future<void> Function()? callback,
    void Function(Object error, StackTrace trace)? onFailure,
  }) : _isDisposed = isDisposed,
       _callback = callback,
       _onFailure = onFailure;

  final bool Function() _isDisposed;
  final Future<void> Function()? _callback;
  final void Function(Object error, StackTrace trace)? _onFailure;
  Future<void>? _inFlight;
  bool _followUpRequested = false;

  bool get hasCallback => _callback != null;

  Future<bool> dispatchForDeveloper({
    required bool developerModeEnabled,
    required bool suppressAutomaticRepair,
  }) async {
    if (!developerModeEnabled ||
        _isDisposed() ||
        suppressAutomaticRepair ||
        _callback == null) {
      return false;
    }
    await dispatch(suppressAutomaticRepair: suppressAutomaticRepair);
    return true;
  }

  Future<void> dispatch({required bool suppressAutomaticRepair}) {
    final callback = _callback;
    if (_isDisposed() || suppressAutomaticRepair || callback == null) {
      return Future<void>.value();
    }

    final runningDispatch = _inFlight;
    if (runningDispatch != null) {
      // A newly available key can arrive while the preceding sweep is still
      // decrypting. Keep one trailing sweep so that key is not stranded.
      _followUpRequested = true;
      return runningDispatch;
    }

    final completer = Completer<void>();
    final dispatch = completer.future;
    _inFlight = dispatch;
    unawaited(_run(completer, dispatch, callback));
    return dispatch;
  }

  Future<void> _run(
    Completer<void> completer,
    Future<void> dispatchFuture,
    Future<void> Function() callback,
  ) async {
    try {
      // The diagnostics object can be disposed after a stale observation is
      // recorded but before this detached callback begins.
      if (!_isDisposed()) {
        await callback();
      }
    } catch (error, trace) {
      _onFailure?.call(error, trace);
    } finally {
      if (identical(_inFlight, dispatchFuture)) {
        _inFlight = null;
      }
      if (_followUpRequested && !_isDisposed()) {
        _followUpRequested = false;
        unawaited(this.dispatch(suppressAutomaticRepair: false));
      }
      completer.complete();
    }
  }
}

/// Couples an already-tracked missing session with the retry that becomes
/// possible when its matching room key arrives.
class MatrixLateRoomKeyRetryCoordinator {
  MatrixLateRoomKeyRetryCoordinator({
    required MatrixMissingRoomSessionStalenessTracker tracker,
    required MatrixPersistentRequestableSessionRepairDispatcher dispatcher,
    required bool suppressAutomaticRepair,
  }) : _tracker = tracker,
       _dispatcher = dispatcher,
       _suppressAutomaticRepair = suppressAutomaticRepair;

  final MatrixMissingRoomSessionStalenessTracker _tracker;
  final MatrixPersistentRequestableSessionRepairDispatcher _dispatcher;
  final bool _suppressAutomaticRepair;

  MatrixMissingRoomSessionResolvedSummary? recordRoomKeyReceived({
    required String? roomId,
    required String? sessionId,
  }) {
    final summary = _tracker.recordRoomKeyReceived(
      roomId: roomId,
      sessionId: sessionId,
    );
    if (summary != null) {
      unawaited(
        _dispatcher.dispatch(suppressAutomaticRepair: _suppressAutomaticRepair),
      );
    }
    return summary;
  }
}

class MatrixMissingRoomSessionStalenessTracker {
  MatrixMissingRoomSessionStalenessTracker({
    DateTime Function()? now,
    String Function(Object? value)? hash,
    this.staleAfter = const Duration(minutes: 5),
    this.relogAfter = const Duration(minutes: 30),
    this.minObservations = 3,
    this.maxTrackedObservations = 512,
  }) : _now = now ?? DateTime.now,
       _hash = hash ?? MatrixE2eeDiagnostics._hash;

  final DateTime Function() _now;
  final String Function(Object? value) _hash;
  final Duration staleAfter;
  final Duration relogAfter;
  final int minObservations;
  final int maxTrackedObservations;
  final Map<String, _MissingRoomSessionObservation> _observations =
      <String, _MissingRoomSessionObservation>{};

  MatrixMissingRoomSessionStaleSummary? recordMissing({
    required String source,
    required String? roomId,
    required String? senderId,
    required String? sessionId,
    required String? senderKey,
  }) {
    final room = _nonEmpty(roomId);
    final session = _nonEmpty(sessionId);
    if (room == null || session == null) {
      return null;
    }

    final sender = _nonEmpty(senderId) ?? 'unknown';
    final now = _now();
    final key = _observationKey(room, sender, session);
    if (!_observations.containsKey(key)) {
      _evictOldestObservationsIfNeeded();
    }
    final observation = _observations.putIfAbsent(
      key,
      () => _MissingRoomSessionObservation(
        roomId: room,
        senderId: sender,
        sessionId: session,
        senderKey: _nonEmpty(senderKey),
        firstSeenAt: now,
      ),
    );

    observation
      ..observations += 1
      ..latestSeenAt = now
      ..sources.add(source);

    final age = now.difference(observation.firstSeenAt);
    if (observation.observations < minObservations || age < staleAfter) {
      return null;
    }

    final lastLoggedAt = observation.lastLoggedAt;
    if (lastLoggedAt != null && now.difference(lastLoggedAt) < relogAfter) {
      return null;
    }

    observation
      ..lastLoggedAt = now
      ..loggedStale = true;
    return MatrixMissingRoomSessionStaleSummary(
      roomHash: _hash(observation.roomId),
      senderHash: _hash(observation.senderId),
      sessionHash: _hash(observation.sessionId),
      senderKeyHash: _hash(observation.senderKey),
      sourcesLabel: _label(observation.sources),
      observations: observation.observations,
      ageSeconds: age.inSeconds,
    );
  }

  MatrixMissingRoomSessionResolvedSummary? recordRoomKeyReceived({
    required String? roomId,
    required String? sessionId,
  }) {
    final room = _nonEmpty(roomId);
    final session = _nonEmpty(sessionId);
    if (room == null || session == null) {
      return null;
    }

    final matchingEntries = _observations.entries
        .where(
          (entry) =>
              entry.value.roomId == room && entry.value.sessionId == session,
        )
        .toList(growable: false);
    if (matchingEntries.isEmpty) {
      return null;
    }

    for (final entry in matchingEntries) {
      _observations.remove(entry.key);
    }

    final now = _now();
    final senders = <String>{};
    var observations = 0;
    var earliest = matchingEntries.first.value.firstSeenAt;
    for (final entry in matchingEntries) {
      final observation = entry.value;
      senders.add(_hash(observation.senderId));
      observations += observation.observations;
      if (observation.firstSeenAt.isBefore(earliest)) {
        earliest = observation.firstSeenAt;
      }
    }

    return MatrixMissingRoomSessionResolvedSummary(
      roomHash: _hash(room),
      sessionHash: _hash(session),
      sendersLabel: _label(senders),
      observations: observations,
      ageSeconds: now.difference(earliest).inSeconds,
    );
  }

  void _evictOldestObservationsIfNeeded() {
    if (maxTrackedObservations <= 0 ||
        _observations.length < maxTrackedObservations) {
      return;
    }

    // Unresolved observations (sender offline, key never shared) would
    // otherwise accumulate for the lifetime of the diagnostics instance.
    final keysByAge = _observations.entries.toList(growable: true)
      ..sort((a, b) => a.value.latestSeenAt.compareTo(b.value.latestSeenAt));
    final removeCount = _observations.length - maxTrackedObservations + 1;
    for (var i = 0; i < removeCount && i < keysByAge.length; i++) {
      _observations.remove(keysByAge[i].key);
    }
  }

  static String _observationKey(
    String roomId,
    String senderId,
    String sessionId,
  ) {
    return '$roomId\x1f$senderId\x1f$sessionId';
  }

  static String? _nonEmpty(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static String _label(Set<String> values) {
    if (values.isEmpty) {
      return 'none';
    }
    return values.join(',');
  }
}

class MatrixMissingRoomSessionStaleSummary {
  const MatrixMissingRoomSessionStaleSummary({
    required this.roomHash,
    required this.senderHash,
    required this.sessionHash,
    required this.senderKeyHash,
    required this.sourcesLabel,
    required this.observations,
    required this.ageSeconds,
  });

  final String roomHash;
  final String senderHash;
  final String sessionHash;
  final String senderKeyHash;
  final String sourcesLabel;
  final int observations;
  final int ageSeconds;
}

class MatrixMissingRoomSessionResolvedSummary {
  const MatrixMissingRoomSessionResolvedSummary({
    required this.roomHash,
    required this.sessionHash,
    required this.sendersLabel,
    required this.observations,
    required this.ageSeconds,
  });

  final String roomHash;
  final String sessionHash;
  final String sendersLabel;
  final int observations;
  final int ageSeconds;
}

class _MissingRoomSessionObservation {
  _MissingRoomSessionObservation({
    required this.roomId,
    required this.senderId,
    required this.sessionId,
    required this.senderKey,
    required this.firstSeenAt,
  }) : latestSeenAt = firstSeenAt;

  final String roomId;
  final String senderId;
  final String sessionId;
  final String? senderKey;
  final DateTime firstSeenAt;
  DateTime latestSeenAt;
  DateTime? lastLoggedAt;
  int observations = 0;
  bool loggedStale = false;
  final Set<String> sources = <String>{};
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
