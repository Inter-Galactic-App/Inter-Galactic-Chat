import 'dart:async';
import 'package:collection/collection.dart';
import 'package:intergalactic/client/alert.dart';
import 'package:intergalactic/client/auth.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/voip/client_close_call_teardown.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_component.dart';
import 'package:intergalactic/client/components/component_registry.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/error_profile.dart';
import 'package:intergalactic/client/matrix/auth/matrix_sso_login_flow.dart';
import 'package:intergalactic/client/matrix/auth/matrix_username_password_login_flow.dart';
import 'package:intergalactic/client/matrix/components/matrix_sync_listener.dart';
import 'package:intergalactic/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:intergalactic/client/matrix/database/matrix_database.dart';
import 'package:intergalactic/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:intergalactic/client/matrix/matrix_e2ee_diagnostics.dart';
import 'package:intergalactic/client/matrix/matrix_native_implementations.dart';
import 'package:intergalactic/client/matrix/matrix_room_notification_snooze.dart';
import 'package:intergalactic/client/matrix/matrix_room_preview.dart';
import 'package:intergalactic/client/matrix/matrix_user_agent_http_client.dart';
import 'package:intergalactic/client/matrix/web/matrix_client_registry.dart';
import 'package:intergalactic/client/matrix/web/web_restore_snapshot.dart';
import 'package:intergalactic/client/matrix/web/matrix_session_audit.dart';
import 'package:intergalactic/client/room_preview.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/global_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/diagnostic/diagnostics.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/service/background_service_notifications/background_matrix_wake_limiter.dart';
import 'package:intergalactic/utils/list_extension.dart';
import 'package:intergalactic/utils/notifying_list.dart';
import 'package:intergalactic/utils/stored_stream_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:intergalactic/client/client.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/encryption.dart';

import '../../ui/atoms/code_block.dart';
import 'matrix_room.dart';
import 'push_rule_state_cache.dart';
import 'matrix_space.dart';
import 'package:vodozemac/vodozemac.dart' as vod;
import 'package:intergalactic/client/matrix/vodozemac_single_flight.dart';

import 'vodozemac_init.dart';

class MatrixPasswordResetStatus {
  const MatrixPasswordResetStatus({
    required this.supported,
    required this.required,
  });

  final bool supported;
  final bool required;

  static const unsupported = MatrixPasswordResetStatus(
    supported: false,
    required: false,
  );
}

class MatrixPasswordResetStatusException implements Exception {
  const MatrixPasswordResetStatusException(this.statusCode);

  final int statusCode;

  String get message =>
      'Could not check whether this account needs a password reset. Please try again.';

  @override
  String toString() => '$message ($statusCode)';
}

class MatrixClient extends Client {
  static const _backgroundServiceWakeSyncTimeout = Duration(seconds: 15);
  static const _matrixWakeSyncMinInterval = Duration(seconds: 12);
  static const passwordResetRequiredFlag =
      'org.intergalactic.password_reset_required';
  static const _passwordResetStatusPath =
      '_synapse/client/intergalactic/password-reset/status';
  static const _passwordResetStatusTimeout = Duration(seconds: 10);

  late matrix.Client _matrixClient;
  late final List<Component<MatrixClient>> componentsInternal;
  StreamSubscription<matrix.SyncUpdate>? _matrixSyncSubscription;
  StreamSubscription<matrix.SyncStatusUpdate>? _syncStatusSubscription;
  late final MatrixE2eeDiagnostics _e2eeDiagnostics;
  late final MatrixRoomNotificationSnoozes _roomNotificationSnoozes;
  Future<void>? _legacyRoomNotificationSnoozeMigration;

  Future? firstSync;

  bool firstSyncComplete = false;
  Future<void>? _matrixSdkInitInFlight;
  bool _matrixSdkInitialized = false;

  /// When true, session refreshes are suppressed to avoid interrupting
  /// an active key verification flow.
  bool _verificationInProgress = false;
  Future<void>? _sessionRepairInFlight;
  Future<void>? _decryptSweepInFlight;
  DateTime? _lastSessionRepairAt;
  Future<void>? _softLogoutRefreshInFlight;
  Future<void>? _deviceDisplayNameUpdateInFlight;
  bool _isClosed = false;

  void setVerificationInProgress(bool inProgress) {
    _verificationInProgress = inProgress;
  }

  Future<void> _runSerializedSessionRepair({
    required String waitLog,
    required String skipLog,
    required String startLog,
    required Future<void> Function() action,
    Duration minInterval = const Duration(seconds: 20),
  }) async {
    final repairInFlight = _sessionRepairInFlight;
    if (repairInFlight != null) {
      Log.i(waitLog);
      await repairInFlight;
      return;
    }

    final now = DateTime.now();
    if (_lastSessionRepairAt != null &&
        now.difference(_lastSessionRepairAt!) < minInterval) {
      Log.w(skipLog);
      return;
    }

    _lastSessionRepairAt = now;
    Log.i(startLog);
    final repairFuture = action();
    _sessionRepairInFlight = repairFuture;

    try {
      await repairFuture;
    } finally {
      if (identical(_sessionRepairInFlight, repairFuture)) {
        _sessionRepairInFlight = null;
      }
    }
  }

  matrix.MediaConfig? config;

  matrix.Client get matrixClient => _matrixClient;

  /// Whether this client runs the persistent sync loop at all. False for the
  /// Android bubble and the headless notification service, which is why
  /// [resumeSyncAfterDatabaseRelease] cannot simply set `backgroundSync` true.
  bool _persistentSyncEnabled = false;

  /// B5. Stops the sync loop and waits for the transaction it holds.
  ///
  /// The SDK wraps sync processing in one database transaction held in a field
  /// for the whole of a large sync, so a release attempted mid-sync is refused.
  /// `abortSync` waits for that transaction before returning, which is the
  /// "let the in-flight transaction finish" step of the release trigger, and it
  /// must run BEFORE the wrapper's quiescence is polled - otherwise the next
  /// sync starts a new transaction and the poll never sees quiet.
  Future<void> suspendSyncForDatabaseRelease() async {
    if (_isClosed) {
      return;
    }
    await _matrixClient.abortSync();
  }

  /// B5. Restarts the sync loop once every released database is established.
  ///
  /// Not before: sync against a released wrapper throws a `StateError` on its
  /// first query, loudly and by design. The trigger calls this only after
  /// `reestablish()` reported `established` for every database it released.
  void resumeSyncAfterDatabaseRelease() {
    if (_isClosed || !_persistentSyncEnabled) {
      return;
    }
    _matrixClient.backgroundSync = true;
  }

  /// Raw homeserver access token for this session. Exposed only for
  /// developer/debug tooling (e.g. the developer settings token viewer);
  /// never surface this in ordinary UI or logs.
  String? get debugAccessToken => _matrixClient.accessToken;

  /// Device id for this session, shown alongside [debugAccessToken] in the
  /// developer token viewer.
  String? get debugDeviceId => _matrixClient.deviceID;

  /// Homeserver origin this session authenticates against, shown alongside
  /// [debugAccessToken] in the developer token viewer.
  String? get debugHomeserverUrl =>
      (_matrixClient.homeserver ?? _matrixClient.baseUri)?.toString();

  late String _id;

  final NotifyingList<Room> _rooms = NotifyingList.empty(growable: true);
  final NotifyingList<Space> _spaces = NotifyingList.empty(growable: true);

  final NotifyingList<Peer> _peers = NotifyingList.empty(growable: true);

  final Map<String, Peer> _peersMap = {};

  final StreamController<void> _onSync = StreamController.broadcast();
  final StreamController<void> _onSelfUpdated = StreamController.broadcast();

  matrix.NativeImplementations get nativeImplentations => BuildConfig.WEB
      ? const matrix.NativeImplementationsDummy()
      : NativeImplementationsCustom(compute);

  MatrixClient({
    required String identifier,
    required matrix.DatabaseApi database,
  }) {
    if (Log.verboseDiagnosticsEnabled) {
      matrix.Logs().level = matrix.Level.verbose;
    } else {
      matrix.Logs().level = matrix.Level.warning;
    }

    _id = identifier;
    _matrixClient = _createMatrixClient(identifier, database);
    _roomNotificationSnoozes = MatrixRoomNotificationSnoozes(
      client: _matrixClient,
      clientId: identifier,
      onRoomChanged: _notifyRoomNotificationSnoozeChanged,
    );
    _e2eeDiagnostics = MatrixE2eeDiagnostics(
      client: _matrixClient,
      clientId: identifier,
      suppressAutomaticRepair: isBubble,
      onPersistentRequestableSessionFailure:
          _repairPersistentRequestableRoomKeyDelivery,
      onRequestableRoomKeyReceived: _retryDecryptAfterRequestableRoomKey,
    )..start();

    self = ErrorProfile();

    _matrixSyncSubscription = _matrixClient.onSync.stream.listen((update) {
      runZoned(
        () => onMatrixClientSync(update),
        zoneValues: {
          Log.matrixNetworkOperationZoneKey: Log.matrixSyncDispatchOperation,
        },
      );
    });
    componentsInternal = ComponentRegistry.getMatrixComponents(this);
  }

  static Future<MatrixClient> create(String identifier) async {
    final database = await getMatrixDatabase(identifier);
    return MatrixClient(identifier: identifier, database: database);
  }

  static String hash(String name) {
    var bytes = utf8.encode(name);
    var hash = sha256.convert(bytes);
    return hash.toString();
  }

  static String _matrixLogHash(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) {
      return 'none';
    }
    return hash(text).substring(0, 12);
  }

  static String _matrixLogError(Object error) => error.runtimeType.toString();

  @override
  bool get supportsE2EE => true;

  @override
  int? get maxFileSize => config?.mUploadSize;

  @override
  String get identifier => _id;

  @override
  Stream<void> get onSelfUpdated => _onSelfUpdated.stream;

  @override
  Stream<int> get onPeerAdded => _peers.onAdd;

  @override
  Stream<int> get onRoomAdded => _rooms.onAdd;

  @override
  Stream<int> get onSpaceAdded => _spaces.onAdd;

  @override
  Stream<int> get onRoomRemoved => _rooms.onRemove;

  @override
  Stream<int> get onSpaceRemoved => _spaces.onRemove;

  @override
  Stream<void> get onSync => _onSync.stream;

  @override
  List<Peer> get peers => _peers;

  @override
  List<Room> get rooms => _rooms;

  @override
  List<Room> get singleRooms => throw UnimplementedError();

  @override
  List<Space> get spaces => _spaces;

  @override
  StoredStreamController<ClientConnectionStatusUpdate> connectionStatusChanged =
      StoredStreamController<ClientConnectionStatusUpdate>();

  static String get matrixClientOlmMissingMessage => Intl.message(
    "libolm is not installed or was not found. End to End Encryption will not be available until this is resolved",
    name: "matrixClientOlmMissingMessage",
    desc: "Text that explains to the user that libolm dependency is not found",
  );

  static String get matrixClientVodozemacMissingMessage => Intl.message(
    "Encryption could not be initialized for this session. End-to-end encrypted messages will not be available until this is resolved.",
    name: "matrixClientVodozemacMissingMessage",
    desc: "Warning shown after Matrix encryption initialization attempts fail",
  );

  static String get matrixClientEncryptionWarningTitle => Intl.message(
    "Encryption Warning",
    name: "matrixClientEncryptionWarningTitle",
    desc: "Title of a warning about encryption",
  );

  static const int webSessionBootstrapSchemaVersion = 1;

  static Future<void> _clearWebSessionBootstrapStateIfOwner(
    String clientName,
  ) async {
    final bootstrapState = preferences.getWebSessionBootstrapState();
    if (bootstrapState != null && bootstrapState['clientId'] == clientName) {
      await preferences.clearWebSessionBootstrapState();
    }
  }

  static Future<WebRestoreSnapshot?> loadFromDB(
    ClientManager manager, {
    bool isBackgroundService = false,
  }) async {
    return await Diagnostics.general.timeAsync("loadFromDB", () async {
      if (!BuildConfig.WEB) {
        final clients = preferences.getRegisteredMatrixClients();
        final futures = <Future<dynamic>>[_checkSystem(manager)];

        if (clients != null) {
          for (final clientName in clients) {
            final client = await MatrixClient.create(clientName);
            manager.addClient(client);
            futures.add(
              Diagnostics.general.timeAsync(
                "Initializing client=${_matrixLogHash(clientName)}",
                () async {
                  try {
                    await client.init(
                      true,
                      isBackgroundService: isBackgroundService,
                    );
                  } catch (error, trace) {
                    Log.onError(
                      error,
                      trace,
                      content:
                          "Unable to load client "
                          "client=${_matrixLogHash(clientName)} from database",
                    );

                    if (!client._setBasicSelfProfileIfLoggedIn()) {
                      client._setSelfProfile(ErrorProfile());
                    }
                    manager.alertManager.addAlert(
                      Alert(
                        AlertType.warning,
                        messageGetter: () =>
                            "One of the registered accounts (${clientName.substring(0, 8)}...) was unable to load correctly, please check the logs for more details",
                        titleGetter: () => "Unable to load account",
                      ),
                    );
                  }
                },
              ),
            );
          }
        }

        await Future.wait(futures);
        return null;
      }

      final storedPreferenceClients =
          preferences.getRegisteredMatrixClients() ?? const <String>[];
      final notesByClientId = <String, String>{};
      final restoredClientIds = <String>[];
      final missingStoredSessionClientIds = <String>[];
      final recoverableFailureClientIds = <String>[];
      final corruptFailureClientIds = <String>[];
      Map<String, dynamic> storageDiagnostics = const <String, dynamic>{};

      if (BuildConfig.WEB) {
        storageDiagnostics =
            await MatrixClientRegistry.collectStorageDiagnostics();
        MatrixSessionAudit.record(
          'Restore storage diagnostics: navigator.storage=${storageDiagnostics['navigatorStorageExists']}, persisted=${storageDiagnostics['persisted']}, persist=${storageDiagnostics['persist']}',
        );
      }

      final clients = await MatrixClientRegistry.resolveRegisteredClientIds(
        storedPreferenceClients,
      );

      if (clients.isEmpty) {
        MatrixSessionAudit.record(
          'No registered Matrix clients were found in preferences or the durable web registry.',
          restoreDecision: true,
        );
      } else if (storedPreferenceClients.isEmpty) {
        MatrixSessionAudit.record(
          'Recovered ${clients.length} registered Matrix client(s) from the durable web registry after the preferences registry was empty.',
          restoreDecision: true,
        );
      } else if (!const ListEquality<String>().equals(
        clients,
        storedPreferenceClients,
      )) {
        MatrixSessionAudit.record(
          'Recovered ${clients.length} registered Matrix client(s) after reconciling preferences with the durable web registry.',
          restoreDecision: true,
        );
      } else {
        MatrixSessionAudit.record(
          'Restoring ${clients.length} registered Matrix client(s) from the preferences registry.',
          restoreDecision: true,
        );
      }

      if (!const ListEquality<String>().equals(
        clients,
        storedPreferenceClients,
      )) {
        await preferences.setRegisteredMatrixClients(clients);
      }

      // On web, encryption runs on the main isolate against
      // NativeImplementationsDummy, so vodozemac must already be initialized
      // before any client.init() reaches its crypto setup. Awaiting it here
      // instead of racing it inside Future.wait keeps a slow cold WASM load
      // from leaving the whole restored session without encryption — which is
      // what left the web Security screen stuck on "wait for sync".
      await _checkSystem(manager);

      final futures = <Future<dynamic>>[];

      for (final clientName in clients) {
        final client = await MatrixClient.create(clientName);
        final storedClient = await client.getMatrixClient().database.getClient(
          clientName,
        );

        if (storedClient == null) {
          final note =
              'Matrix client $clientName opened its IndexedDB database, but the stored session record is missing.';
          notesByClientId[clientName] = note;
          missingStoredSessionClientIds.add(clientName);
          MatrixSessionAudit.record(note, restoreDecision: true);
          try {
            await client.close();
          } catch (error) {
            MatrixSessionAudit.record(
              'Unable to close Matrix client client=${_matrixLogHash(clientName)} '
              'after detecting a missing stored session record '
              'error=${_matrixLogError(error)}',
            );
          }
          continue;
        }

        futures.add(
          Diagnostics.general.timeAsync(
            "Initializing client=${_matrixLogHash(clientName)}",
            () async {
              try {
                await client.init(
                  true,
                  isBackgroundService: isBackgroundService,
                );
                restoredClientIds.add(clientName);
                notesByClientId[clientName] =
                    'Matrix client $clientName restored successfully from local web storage.';
                manager.addClient(client);
              } catch (error, trace) {
                if (_isOtkUploadError(error)) {
                  // "One time key already exists" is non-fatal. It means OTKs
                  // were uploaded during a recent session (e.g. a soft-logout
                  // repair with oneShotSync) and are still on the server. The
                  // session is healthy; the SDK background sync will reconcile
                  // OTK state automatically. Add the client rather than
                  // destroying it.
                  if (client.getMatrixClient().isLogged()) {
                    Log.w(
                      '[Web] Client client=${_matrixLogHash(clientName)} had '
                      'a non-fatal OTK upload error during init '
                      'error=${_matrixLogError(error)}. Session appears '
                      'healthy — adding client.',
                    );
                    restoredClientIds.add(clientName);
                    notesByClientId[clientName] =
                        'Matrix client $clientName restored after a non-fatal one-time-key upload conflict.';
                    manager.addClient(client);
                  } else {
                    // OTK error but not logged in — something else went wrong.
                    Log.onError(
                      error,
                      trace,
                      content:
                          'Unable to load client client=${_matrixLogHash(clientName)} '
                          'from database (OTK error, client not logged in)',
                    );
                    final note =
                        'Matrix client $clientName hit a one-time-key upload conflict during restore, but the session was no longer logged in afterwards.';
                    notesByClientId[clientName] = note;
                    corruptFailureClientIds.add(clientName);
                    MatrixSessionAudit.record(
                      '$note Error: ${_matrixLogError(error)}',
                      restoreDecision: true,
                    );
                    try {
                      await client.close();
                    } catch (closeError) {
                      MatrixSessionAudit.record(
                        'Unable to close Matrix client '
                        'client=${_matrixLogHash(clientName)} after a corrupt '
                        'restore classification error=${_matrixLogError(closeError)}',
                      );
                    }
                  }
                } else if (client.getMatrixClient().isLogged()) {
                  final note =
                      'Matrix client $clientName kept a logged-in session after init failed, so the session was preserved for recovery instead of being discarded.';
                  notesByClientId[clientName] = note;
                  recoverableFailureClientIds.add(clientName);
                  MatrixSessionAudit.record(
                    '$note Error: ${_matrixLogError(error)}',
                    restoreDecision: true,
                  );
                  manager.addClient(client);
                } else {
                  Log.onError(
                    error,
                    trace,
                    content:
                        "Unable to load client "
                        "client=${_matrixLogHash(clientName)} from database",
                  );
                  final note =
                      'Matrix client $clientName failed to initialize from local web storage and no logged-in session remained afterwards.';
                  notesByClientId[clientName] = note;
                  corruptFailureClientIds.add(clientName);
                  MatrixSessionAudit.record(
                    '$note Error: ${_matrixLogError(error)}',
                    restoreDecision: true,
                  );
                  try {
                    await client.close();
                  } catch (closeError) {
                    MatrixSessionAudit.record(
                      'Unable to close Matrix client '
                      'client=${_matrixLogHash(clientName)} after a corrupt '
                      'restore classification error=${_matrixLogError(closeError)}',
                    );
                  }
                }
              }
            },
          ),
        );
      }

      await Future.wait(futures);

      if (clients.isNotEmpty && restoredClientIds.isEmpty) {
        MatrixSessionAudit.record(
          'No recoverable Matrix client sessions were found after checking the registered client databases.',
          restoreDecision: true,
        );
      }

      return WebRestoreSnapshot(
        candidateClientIds: clients,
        restoredClientIds: restoredClientIds,
        missingStoredSessionClientIds: missingStoredSessionClientIds,
        recoverableFailureClientIds: recoverableFailureClientIds,
        corruptFailureClientIds: corruptFailureClientIds,
        storageDiagnostics: storageDiagnostics,
        notesByClientId: notesByClientId,
      );
    });
  }

  /// Returns true when [error] is a one-time-key upload conflict.
  ///
  /// "One time key already exists" means OTKs were uploaded by a recent
  /// session (e.g. via oneShotSync during a soft-logout repair) and are still
  /// on the server. This is non-fatal: the session is healthy and the SDK will
  /// reconcile OTK state on the next background sync cycle.
  static bool _isOtkUploadError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('upload key') ||
        msg.contains('one time key') ||
        msg.contains('already exists');
  }

  /// Coarse, human-readable progress for the encryption-init step of startup,
  /// or null when nothing is in flight.
  ///
  /// Encryption init is deliberately awaited before any client is restored on
  /// web, so a slow cold WASM download holds up startup for up to the full
  /// retry budget. That ordering is a fail-closed requirement -- restoring a
  /// session before crypto is ready is what left web sessions unencrypted for
  /// their whole lifetime -- so the mitigation is to make the wait legible
  /// rather than to shorten or parallelise it.
  ///
  /// Deliberately coarse: stage and attempt counter only. No account, device,
  /// session, or key material may be published here, since this string is
  /// rendered on screen and may be captured in screenshots or bug reports.
  static final ValueNotifier<String?> encryptionStartupProgress =
      ValueNotifier<String?>(null);

  /// Encryption readiness, for surfaces that act DIRECTLY on encryption.
  ///
  /// The progress string above is for a person watching startup; it is copy,
  /// it is cleared on every exit path, and nothing can decide anything from
  /// it. This is the state a caller can read: `pending` until vodozemac
  /// initializes, `unavailable` once the bounded retry budget is exhausted.
  /// Both are fail-closed - a surface that acts on encryption must not offer
  /// itself as operable in either.
  ///
  /// It does not weaken the restore ordering. Clients are still not created
  /// until initialization returns; this only makes the state legible to
  /// everything that used to have to assume it.
  static final ValueNotifier<EncryptionAvailability> encryptionAvailability =
      ValueNotifier<EncryptionAvailability>(EncryptionAvailability.pending);

  static Future<void> _checkSystem(ClientManager clientManager) async {
    // A cold web WASM download of vodozemac can take several seconds on a slow
    // connection, so a single 5s attempt used to time out and leave encryption
    // disabled for the entire session. Retry with generous headroom before
    // giving up. Later attempts are cheap: the file is cached after the first
    // download, and initVodozemacForPlatform short-circuits once initialized.
    const attemptTimeout = Duration(seconds: 20);
    const maxAttempts = 3;

    try {
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        encryptionStartupProgress.value = attempt == 1
            ? 'Preparing encryption.'
            : 'Preparing encryption (attempt $attempt of $maxAttempts).';
        try {
          // initVodozemacForPlatform handles the platform split:
          // iOS uses the statically linked process library, web uses WASM, and
          // other platforms use the normal flutter_vodozemac dynamic loader.
          if (!vod.isInitialized()) {
            await initVodozemacForPlatform().timeout(attemptTimeout);
          }
          if (vod.isInitialized()) {
            encryptionAvailability.value = EncryptionAvailability.ready;
            return;
          }
          throw Exception("Vodozemac failed to initialize!");
        } catch (exception, trace) {
          if (attempt < maxAttempts) {
            Log.w(
              "Vodozemac initialization attempt $attempt/$maxAttempts failed, "
              "retrying: ${_matrixLogError(exception)}",
            );
            await Future<void>.delayed(const Duration(milliseconds: 500));
            continue;
          }

          Log.onError(
            exception,
            trace,
            content:
                "Failed to initialize vodozemac after $maxAttempts attempts",
          );
          // The budget is spent. Say so in state as well as in an alert: an
          // alert is dismissible and unreadable by code, and the surfaces
          // that act on encryption need to fail closed for the rest of this
          // session rather than look operable.
          encryptionAvailability.value = EncryptionAvailability.unavailable;
          clientManager.alertManager.addAlert(
            Alert(
              AlertType.warning,
              titleGetter: () => matrixClientEncryptionWarningTitle,
              messageGetter: () => matrixClientVodozemacMissingMessage,
            ),
          );
        }
      }
    } finally {
      // Cleared on every exit path -- success, exhausted retries, or a throw --
      // so a stale "preparing encryption" line can never outlive the step.
      encryptionStartupProgress.value = null;
    }
  }

  static matrix.NativeImplementations get nativeImplementations =>
      BuildConfig.WEB
      ? const matrix.NativeImplementationsDummy()
      : matrix.NativeImplementationsIsolate(
          compute,
          vodozemacInit: initVodozemacForPlatform,
        );

  Future<void> _ensureMatrixSdkInitialized(
    bool loadingFromCache, {
    bool isBackgroundService = false,
  }) async {
    final disablePersistentSync = isBackgroundService || isBubble;
    _persistentSyncEnabled = !disablePersistentSync;
    if (_matrixSdkInitialized) {
      if (disablePersistentSync) {
        _matrixClient.backgroundSync = false;
      }
      return;
    }

    final initInFlight = _matrixSdkInitInFlight;
    if (initInFlight != null) {
      await initInFlight;
      return;
    }

    // matrix.Client.login() already runs the SDK init() internally with the
    // new credentials (including the first sync), and calling init() again on
    // a logged-in SDK client throws ClientInitPreconditionError. Without this
    // guard the post-login init(false) aborted before _updateOwnProfile and
    // component postLoginInit ever ran, leaving the session on the basic
    // avatar-less self profile until the app was fully restarted.
    if (_matrixClient.onLoginStateChanged.value == matrix.LoginState.loggedIn) {
      _matrixSdkInitialized = true;
      if (disablePersistentSync) {
        _matrixClient.backgroundSync = false;
      }
      return;
    }

    final initFuture = Diagnostics.general.timeAsync(
      "Matrix client init",
      () async {
        if (disablePersistentSync) {
          _matrixClient.backgroundSync = false;
        }

        await runZoned(
          () => _matrixClient.init(
            waitForFirstSync: !loadingFromCache,
            waitUntilLoadCompletedLoaded: true,
            onInitStateChanged: (state) {
              if (state == matrix.InitState.migratingDatabase) {
                Log.w("Matrix Database is migrating");
              }
            },
          ),
          zoneValues: {
            Log.matrixNetworkOperationZoneKey: Log.matrixSdkLifecycleOperation,
          },
        );

        if (disablePersistentSync) {
          _matrixClient.backgroundSync = false;
        }
      },
    );

    _matrixSdkInitInFlight = initFuture;

    try {
      await initFuture;
      _matrixSdkInitialized = true;
    } finally {
      if (identical(_matrixSdkInitInFlight, initFuture)) {
        _matrixSdkInitInFlight = null;
      }
    }
  }

  @override
  Future<void> init(
    bool loadingFromCache, {
    bool isBackgroundService = false,
  }) async {
    if (isBubble) {
      Log.i(
        'Initializing Matrix client for Android notification bubble with persistent background sync disabled',
        category: LogCategory.matrix,
        source: 'matrix-client',
      );
    }

    await _ensureMatrixSdkInitialized(
      loadingFromCache,
      isBackgroundService: isBackgroundService,
    );

    if (isBackgroundService) {
      await _runBackgroundServiceWakeSync();
      return;
    }

    await _updateOwnProfile();
    if (isLoggedIn()) {
      unawaited(_ensureCurrentDeviceDisplayName());
    }

    if (firstSync == null) {
      firstSync = _runStartupOneShotSync();
    }

    _matrixClient.getConfig().then((value) {
      config = value;
    });

    _updateRoomslist();
    _updateSpacesList();
    if (BuildConfig.WEB) {
      unawaited(persistDeviceProfile());
    }
    if (isLoggedIn()) {
      _initializeRestoredDirectMessages();
    }
  }

  Future<void> _runBackgroundServiceWakeSync() async {
    if (!isLoggedIn()) {
      return;
    }

    final shouldRunWakeSync = await BackgroundMatrixWakeLimiter.claim(
      _matrixClient.clientName,
      minInterval: _matrixWakeSyncMinInterval,
    );
    if (!shouldRunWakeSync) {
      Log.i(
        "Skipping Android background Matrix wake sync for "
        "client=${_matrixLogHash(_matrixClient.clientName)}; "
        "another wake ran recently.",
      );
      _matrixClient.backgroundSync = false;
      return;
    }

    _matrixClient.backgroundSync = false;
    Log.i(
      "Running bounded Android background Matrix wake sync for "
      "client=${_matrixLogHash(_matrixClient.clientName)}",
    );
    try {
      await _matrixClient.oneShotSync(
        timeout: _backgroundServiceWakeSyncTimeout,
      );
    } catch (e, s) {
      Log.w("Background Matrix wake sync failed");
      Log.onError(e, s);
    } finally {
      _matrixClient.backgroundSync = false;
    }
  }

  Future<void> _runStartupOneShotSync() async {
    if (isBubble) {
      final shouldRunStartupSync = await BackgroundMatrixWakeLimiter.claim(
        _matrixClient.clientName,
        minInterval: _matrixWakeSyncMinInterval,
      );
      if (!shouldRunStartupSync) {
        Log.i(
          "Skipping bubble startup Matrix sync for "
          "client=${_matrixLogHash(_matrixClient.clientName)}; "
          "another wake ran recently.",
        );
        return;
      }

      Log.i(
        "Running bubble startup Matrix sync for "
        "client=${_matrixLogHash(_matrixClient.clientName)}",
      );
    }

    await _matrixClient.oneShotSync();
    firstSyncComplete = true;
  }

  void _initializeRestoredDirectMessages() {
    getComponent<DirectMessagesComponent>()?.initializeDirectMessageRooms();
  }

  void onMatrixClientSync(matrix.SyncUpdate update) {
    if (_isClosed || _onSync.isClosed) {
      return;
    }

    _handleComponentSync(update);
    _roomNotificationSnoozes.onSync(update);
    unawaited(_reconcileRoomNotificationSnoozes());
    _invalidatePushRuleCaches(update);

    _onSync.add(null);
    _updateRoomslist();
    _updateSpacesList();
    _handleSpaceChildren(update);
  }

  /// Room and space wrappers cache their push-rule state on first read, and
  /// before BUG-319 only a local `setPushRule` on that same instance cleared
  /// it. A rule changed on another device, or through a different wrapper for
  /// the same id, was therefore invisible until a restart rebuilt the
  /// instance. `globalPushRules` is derived from the `m.push_rules` account
  /// data, so that event arriving is exactly when the caches are stale.
  @visibleForTesting
  void invalidatePushRuleCaches(matrix.SyncUpdate update) =>
      _invalidatePushRuleCaches(update);

  void _invalidatePushRuleCaches(matrix.SyncUpdate update) {
    if (!syncCarriesPushRules(update)) {
      return;
    }

    for (final holder in [...rooms, ...spaces]) {
      if (holder is PushRuleCacheHolder) {
        holder.invalidatePushRuleCache();
      }
    }
  }

  MatrixRoomNotificationSnoozes get roomNotificationSnoozes =>
      _roomNotificationSnoozes;

  void _notifyRoomNotificationSnoozeChanged(String roomId) {
    final room = getRoom(roomId);
    if (room is MatrixRoom) {
      room.notifyNotificationSnoozeChanged();
    }
  }

  Future<void> _reconcileRoomNotificationSnoozes() async {
    final migration = _legacyRoomNotificationSnoozeMigration ??=
        _migrateLegacyRoomNotificationSnoozes();
    await migration;
    await _roomNotificationSnoozes.reconcile();
  }

  Future<void> _migrateLegacyRoomNotificationSnoozes() async {
    if (!preferences.isInit) {
      await preferences.init();
    }

    final now = DateTime.now();
    final legacySnoozes = preferences.getRoomNotificationSnoozes(
      now: now,
      includeExpired: true,
    );
    for (final snooze in legacySnoozes.values) {
      if (snooze.clientId != identifier) {
        continue;
      }
      try {
        if (snooze.isActive(now) &&
            _roomNotificationSnoozes.get(snooze.roomId, now: now) == null) {
          await _roomNotificationSnoozes.set(
            snooze.roomId,
            snooze.snoozedUntil.difference(now),
            source: 'legacy_migration',
            now: now,
          );
        }
        await preferences.clearRoomNotificationSnooze(
          clientId: snooze.clientId,
          roomId: snooze.roomId,
        );
      } catch (error, trace) {
        Log.w(
          'Keeping legacy room notification snooze after sync migration '
          'failure error=${_matrixLogError(error)}',
          category: LogCategory.notifications,
          source: 'notification-snooze',
        );
        Log.onError(error, trace);
      }
    }
  }

  void _handleSpaceChildren(matrix.SyncUpdate update) {
    if (update.rooms?.join?.isNotEmpty == true) {
      for (var pair in update.rooms!.join!.entries) {
        var id = pair.key;
        var update = pair.value;

        if (update.timeline?.events?.isNotEmpty == true) {
          for (var event in update.timeline!.events!) {
            if (event.type == matrix.EventTypes.SpaceChild) {
              var space = getSpace(id);
              (space as MatrixSpace?)?.updateRoomsList();
            }
          }
        }
      }
    }
  }

  void _handleComponentSync(matrix.SyncUpdate update) {
    var roomUpdates = update.rooms?.join;
    if (roomUpdates != null) {
      for (var key in roomUpdates.keys) {
        var room = getRoom(key);
        if (room != null) {
          var components = room.getAllComponents();
          for (var comp in components) {
            if (comp is MatrixRoomSyncListener) {
              (comp as MatrixRoomSyncListener).onSync(roomUpdates[key]!);
            }
          }
        }
      }
    }
  }

  @override
  bool isLoggedIn() => _matrixClient.isLogged();

  matrix.Client _createMatrixClient(String name, matrix.DatabaseApi database) {
    var client = matrix.Client(
      name,
      verificationMethods: {
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.numbers,
      },
      importantStateEvents: {
        "im.ponies.room_emotes",
        "m.room.power_levels",
        "m.room.join_rules",
        "page.codeberg.everypizza.room.banner",
        "chat.commet.calendar_event",
        SoundboardEventTypes.soundState,
        SoundboardEventTypes.userState,
        MatrixVoipRoomComponent.callMemberStateEvent,
      },
      supportedLoginTypes: {
        matrix.AuthenticationTypes.password,
        matrix.AuthenticationTypes.sso,
      },
      onSoftLogout: BuildConfig.WEB
          ? (client) async {
              final refreshInFlight = _softLogoutRefreshInFlight;
              if (refreshInFlight != null) {
                Log.i(
                  'Waiting for the current Matrix soft-logout refresh attempt to finish',
                );
                await refreshInFlight;
                return;
              }

              final refreshFuture = () async {
                try {
                  await _runSerializedSessionRepair(
                    waitLog:
                        'Waiting for the current Matrix session repair before handling soft logout',
                    skipLog:
                        'Skipping Matrix soft-logout refresh because a session repair was attempted recently',
                    startLog: 'Refreshing Matrix session after soft logout',
                    minInterval: Duration.zero,
                    action: _repairSoftLoggedOutSession,
                  );
                } catch (error, trace) {
                  Log.onError(
                    error,
                    trace,
                    content:
                        'Failed to refresh Matrix session after soft logout',
                  );
                  rethrow;
                }
              }();

              _softLogoutRefreshInFlight = refreshFuture;
              try {
                await refreshFuture;
              } finally {
                if (identical(_softLogoutRefreshInFlight, refreshFuture)) {
                  _softLogoutRefreshInFlight = null;
                }
              }
            }
          : null,
      httpClient: BuildConfig.WEB ? null : MatrixUserAgentHttpClient(),
      nativeImplementations: nativeImplementations,
      database: database,
      logLevel: matrix.Level.verbose,
      shareKeysWith: MatrixE2eeDiagnostics.shareKeysWithForPreference(
        preferences.matrixKeySharingPolicy.value,
      ),
    );

    _syncStatusSubscription = client.onSyncStatus.stream.listen(
      onSyncStatusChanged,
    );

    return client;
  }

  matrix.Client getMatrixClient() {
    return _matrixClient;
  }

  MatrixE2eeTrustStatus get e2eeTrustStatus =>
      _e2eeDiagnostics.buildTrustStatus();

  matrix.ShareKeysWith applyConfiguredKeySharingPolicy() {
    return _e2eeDiagnostics.applyConfiguredShareKeysWith();
  }

  Future<void> refreshE2eeTrustStatus() {
    return _e2eeDiagnostics.refreshOwnDeviceKeys();
  }

  Future<MatrixPasswordResetStatus> getPasswordResetStatus() async {
    final baseUri = _matrixClient.baseUri;
    final accessToken = _matrixClient.accessToken;

    if (baseUri == null || accessToken == null || accessToken.isEmpty) {
      return MatrixPasswordResetStatus.unsupported;
    }

    final request = http.Request(
      'GET',
      baseUri.resolveUri(Uri(path: _passwordResetStatusPath)),
    );
    request.headers['authorization'] = 'Bearer $accessToken';

    late final http.StreamedResponse streamedResponse;
    late final http.Response response;
    try {
      streamedResponse = await _matrixClient.httpClient
          .send(request)
          .timeout(_passwordResetStatusTimeout);
      response = await http.Response.fromStream(
        streamedResponse,
      ).timeout(_passwordResetStatusTimeout);
    } on TimeoutException {
      throw const MatrixPasswordResetStatusException(408);
    }

    if (response.statusCode == 404 ||
        response.statusCode == 405 ||
        response.statusCode == 501) {
      return MatrixPasswordResetStatus.unsupported;
    }

    Object? content;
    if (response.body.isNotEmpty) {
      try {
        content = json.decode(response.body);
      } catch (_) {
        content = null;
      }
    }

    if (response.statusCode == 200) {
      if (content is Map) {
        return MatrixPasswordResetStatus(
          supported: true,
          required: content['required'] == true,
        );
      }

      throw MatrixPasswordResetStatusException(response.statusCode);
    }

    if (_jsonRequiresPasswordReset(content)) {
      return const MatrixPasswordResetStatus(supported: true, required: true);
    }

    throw MatrixPasswordResetStatusException(response.statusCode);
  }

  Future<void> changeAccountPassword({
    required String oldPassword,
    required String newPassword,
    bool logoutDevices = false,
  }) async {
    await runWithSessionRepairOnUnknownToken(
      'changing Matrix account password',
      () => _matrixClient.changePassword(
        newPassword,
        oldPassword: oldPassword,
        logoutDevices: logoutDevices,
      ),
    );
  }

  static bool responseRequiresPasswordReset(Object error) {
    return error is matrix.MatrixException &&
        _jsonRequiresPasswordReset(error.raw);
  }

  static String passwordChangeFailureMessage(Object error) {
    if (error is matrix.MatrixException) {
      final message = error.errorMessage.trim();
      if (message.isNotEmpty) {
        return message;
      }
    }

    if (error is MatrixPasswordResetStatusException) {
      return error.message;
    }

    return 'Could not change password. Check the current password and try again.';
  }

  static bool _jsonRequiresPasswordReset(Object? content) {
    if (content is Map) {
      return content[passwordResetRequiredFlag] == true;
    }

    return false;
  }

  static String _normalizeHomeserverOrigin(Uri homeserver) {
    return homeserver.origin.toLowerCase();
  }

  static String _localpartFromUserId(String userId) {
    final normalized = userId.startsWith('@') ? userId.substring(1) : userId;
    final separatorIndex = normalized.indexOf(':');
    if (separatorIndex == -1) {
      return normalized.toLowerCase();
    }

    return normalized.substring(0, separatorIndex).toLowerCase();
  }

  List<Map<String, dynamic>> _registeredDeviceProfilesForHomeserver(
    String homeserverKey,
  ) {
    final registeredClientIds = Set<String>.from(
      preferences.getRegisteredMatrixClients() ?? const <String>[],
    );
    if (registeredClientIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    return preferences
        .getMatrixDeviceProfilesForHomeserver(homeserverKey)
        .where((profile) {
          final clientName = profile['clientName'] as String?;
          return clientName != null && registeredClientIds.contains(clientName);
        })
        .toList();
  }

  String? resolveStoredDeviceIdForLogin({String? usernameHint}) {
    final trimmedUsername = usernameHint?.trim();
    if (trimmedUsername == null || trimmedUsername.isEmpty) {
      return null;
    }

    final homeserver = _matrixClient.homeserver ?? _matrixClient.baseUri;
    if (homeserver == null) {
      return null;
    }

    final homeserverKey = _normalizeHomeserverOrigin(homeserver);
    final profiles = _registeredDeviceProfilesForHomeserver(homeserverKey);
    final normalizedUsername = trimmedUsername.toLowerCase();

    if (normalizedUsername.startsWith('@') &&
        normalizedUsername.contains(':')) {
      final exactMatch = profiles.firstWhereOrNull(
        (profile) =>
            (profile['userId'] as String?)?.toLowerCase() == normalizedUsername,
      );
      return exactMatch == null ? null : exactMatch['deviceId'] as String?;
    }

    final localpartMatches = profiles
        .where(
          (profile) =>
              (profile['localpart'] as String?)?.toLowerCase() ==
              normalizedUsername,
        )
        .toList();

    if (localpartMatches.length == 1) {
      return localpartMatches.first['deviceId'] as String?;
    }

    return null;
  }

  String? resolveStoredDeviceIdForCurrentHomeserver() {
    final homeserver = _matrixClient.homeserver ?? _matrixClient.baseUri;
    if (homeserver == null) {
      return null;
    }

    final profiles = _registeredDeviceProfilesForHomeserver(
      _normalizeHomeserverOrigin(homeserver),
    );
    if (profiles.length != 1) {
      return null;
    }

    return profiles.first['deviceId'] as String?;
  }

  Future<void> persistDeviceProfile() async {
    final userId = _matrixClient.userID;
    final deviceId = _matrixClient.deviceID;
    final homeserver = _matrixClient.homeserver ?? _matrixClient.baseUri;

    if (userId == null || deviceId == null || homeserver == null) {
      return;
    }

    final homeserverKey = _normalizeHomeserverOrigin(homeserver);
    final localpart = _localpartFromUserId(userId);
    final updatedAt = DateTime.now().toUtc().toIso8601String();

    await preferences
        .setMatrixDeviceProfile('$homeserverKey|${userId.toLowerCase()}', {
          'userId': userId,
          'localpart': localpart,
          'deviceId': deviceId,
          'homeserver': homeserverKey,
          'clientName': _matrixClient.clientName,
          'updatedAt': updatedAt,
        });

    await MatrixClientRegistry.upsert({
      'clientId': _matrixClient.clientName,
      'userId': userId,
      'localpart': localpart,
      'deviceId': deviceId,
      'homeserver': homeserverKey,
      'updatedAt': updatedAt,
    });

    await persistWebSessionBootstrapState();
  }

  Future<void> persistWebSessionBootstrapState() async {
    if (!BuildConfig.WEB) {
      return;
    }

    final userId = _matrixClient.userID;
    final deviceId = _matrixClient.deviceID;
    if (userId == null || deviceId == null || !_matrixClient.isLogged()) {
      return;
    }

    final secretStorageReady = await _resolveSecretStorageReadyForBootstrap();
    final existingState = preferences.getWebSessionBootstrapState();
    final existingClientId = existingState == null
        ? null
        : existingState['clientId'];
    final preservedLastHealthyAt =
        (existingClientId == _matrixClient.clientName)
        ? (existingState == null ? null : existingState['lastHealthyAt'])
        : null;

    await preferences.setWebSessionBootstrapState({
      'schemaVersion': webSessionBootstrapSchemaVersion,
      'clientId': _matrixClient.clientName,
      'userId': userId,
      'deviceId': deviceId,
      'secretStorageReady': secretStorageReady,
      'lastHealthyAt': secretStorageReady
          ? DateTime.now().toUtc().toIso8601String()
          : preservedLastHealthyAt,
    });
  }

  Future<bool> _resolveSecretStorageReadyForBootstrap() async {
    final encryption = _matrixClient.encryption;
    if (!_matrixClient.encryptionEnabled || encryption == null) {
      return false;
    }

    try {
      final cryptoIdentityState = await _matrixClient.getCryptoIdentityState();
      final needsRecoveryGate =
          cryptoIdentityState.initialized ||
          encryption.crossSigning.enabled ||
          encryption.keyManager.enabled;
      return !needsRecoveryGate || cryptoIdentityState.connected;
    } catch (error) {
      MatrixSessionAudit.record(
        'Unable to inspect the Matrix crypto identity state while persisting '
        'the web bootstrap record for client=${_matrixLogHash(_id)} '
        'error=${_matrixLogError(error)}',
      );
      return false;
    }
  }

  Future<void> _repairSoftLoggedOutSession() async {
    final storedClient = await _matrixClient.database.getClient(
      _matrixClient.clientName,
    );
    final refreshToken = storedClient?.tryGet<String>('refresh_token');

    if (refreshToken == null || refreshToken.isEmpty) {
      if (BuildConfig.WEB) {
        MatrixSessionAudit.record(
          'Matrix soft-logout repair for client=${_matrixLogHash(_id)} '
          'cannot continue because the local session has no stored refresh token.',
        );
      }
      throw StateError(
        'No refresh token available for Matrix soft-logout repair',
      );
    }

    await _matrixClient.refreshAccessToken();

    if (BuildConfig.WEB) {
      MatrixSessionAudit.record(
        'Matrix soft-logout repair refreshed the access token for '
        'client=${_matrixLogHash(_id)}.',
      );
    }

    // Log encryption state after token refresh so future diagnostics can tell
    // whether the soft-logout disrupted encryption before the sync runs.
    if (BuildConfig.WEB) {
      if (_matrixClient.encryptionEnabled && _matrixClient.encryption != null) {
        MatrixSessionAudit.record(
          'Soft-logout repair for client=${_matrixLogHash(_id)}: '
          'encryption is available after token refresh.',
        );
      } else {
        MatrixSessionAudit.record(
          'Soft-logout repair for client=${_matrixLogHash(_id)}: WARNING - '
          'encryption is NOT available after token refresh. The background sync '
          'loop should restore it.',
        );
      }
    }

    try {
      await _matrixClient.oneShotSync(timeout: const Duration(seconds: 10));
      _updateRoomslist();
      _updateSpacesList();
      await persistDeviceProfile();
      await _ensureSsssAndCrossSigningCached();
    } on matrix.MatrixException catch (error, trace) {
      if (error.error == matrix.MatrixError.M_UNKNOWN_TOKEN) {
        rethrow;
      }

      Log.onError(
        error,
        trace,
        content:
            'Matrix access token refresh succeeded after soft logout, but the immediate sync repair did not complete. The client will retry when connectivity stabilizes.',
      );
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content:
            'Matrix access token refresh succeeded after soft logout, but the immediate sync repair did not complete. The client will retry when connectivity stabilizes.',
      );
    }
  }

  Future<void> refreshSessionAfterResume({bool aggressive = false}) async {
    if (!BuildConfig.WEB) {
      return;
    }

    if (!_matrixClient.isLogged()) return;

    if (_verificationInProgress) {
      Log.i('Skipping Matrix session refresh: key verification in progress');
      return;
    }

    await _runSerializedSessionRepair(
      waitLog:
          'Waiting for the current Matrix session repair before refreshing after app resume',
      skipLog:
          'Skipping Matrix session refresh after app resume because a repair was attempted recently',
      startLog: aggressive
          ? 'Refreshing Matrix session after a long iPhone PWA resume'
          : 'Refreshing Matrix session after app resume/inactivity',
      minInterval: aggressive
          ? const Duration(seconds: 10)
          : const Duration(seconds: 20),
      action: () async {
        try {
          await _runResumeRefresh(aggressive: aggressive);
        } catch (error, trace) {
          Log.onError(
            error,
            trace,
            content: 'Failed to refresh Matrix session after app resume',
          );
        }
      },
    );
  }

  Future<void> _runResumeRefresh({required bool aggressive}) async {
    await _matrixClient.ensureNotSoftLoggedOut(const Duration(minutes: 30));

    if (aggressive) {
      await _matrixClient.oneShotSync(timeout: const Duration(seconds: 10));
      _updateRoomslist();
      _updateSpacesList();
      await persistDeviceProfile();
    }
  }

  Future<void> _ensureSsssAndCrossSigningCached() async {
    final encryption = _matrixClient.encryption;
    if (encryption == null) return;

    try {
      await encryption.ssss.periodicallyRequestMissingCache();
    } catch (error) {
      Log.w(
        'Failed to refresh SSSS cache after inactivity '
        'error=${_matrixLogError(error)}',
      );
    }
  }

  Future<void> retryDecryptAllRooms({bool loadMissingTimelines = true}) async {
    final runningSweep = _decryptSweepInFlight;
    if (runningSweep != null) {
      Log.i('Waiting for encrypted-room decrypt retry already in progress');
      await runningSweep;
      return;
    }

    final sweep = _retryDecryptAllRooms(
      loadMissingTimelines: loadMissingTimelines,
    );
    _decryptSweepInFlight = sweep;

    try {
      await sweep;
    } finally {
      if (identical(_decryptSweepInFlight, sweep)) {
        _decryptSweepInFlight = null;
      }
    }
  }

  Future<void> repairEncryptionSessionsAndRetry({
    bool loadMissingTimelines = true,
  }) async {
    await _e2eeDiagnostics.repairOlmToDevicePath(
      reason: 'manual_security_repair',
      includeSync: true,
      force: true,
    );
    await retryDecryptAllRooms(loadMissingTimelines: loadMissingTimelines);
  }

  /// Runs the developer-only simulation of the automatic persistent
  /// requestable-session repair. The diagnostics layer refuses it outside
  /// Developer mode and retains all normal fail-closed checks.
  Future<bool> runDeveloperPersistentRequestableSessionRepair() {
    return _e2eeDiagnostics.runDeveloperPersistentRequestableSessionRepair();
  }

  Future<void> _repairPersistentRequestableRoomKeyDelivery() async {
    // Fired detached from the diagnostics listener, so close() can land either
    // before it starts or during the bounded sync inside the repair. A decrypt
    // sweep after that walks every encrypted room against a torn-down client.
    if (_isClosed) {
      return;
    }

    await _e2eeDiagnostics.repairOlmToDevicePath(
      reason: 'persistent_requestable_room_key',
      includeSync: true,
    );

    if (_isClosed) {
      return;
    }

    await retryDecryptAllRooms(loadMissingTimelines: false);
  }

  Future<void> _retryDecryptAfterRequestableRoomKey() async {
    if (_isClosed) {
      return;
    }
    await retryDecryptAllRooms(loadMissingTimelines: false);
  }

  Future<void> _retryDecryptAllRooms({
    required bool loadMissingTimelines,
  }) async {
    if (!_matrixClient.encryptionEnabled || _matrixClient.encryption == null) {
      return;
    }

    await _ensureSsssAndCrossSigningCached();

    final initialSync = firstSync;
    if (!firstSyncComplete && initialSync != null) {
      try {
        await initialSync.timeout(const Duration(seconds: 10));
      } catch (error) {
        Log.w(
          'Continuing encrypted-room decrypt retry before first sync completed '
          'error=${_matrixLogError(error)}',
        );
      }
    }

    final encryptedRooms = rooms
        .whereType<MatrixRoom>()
        .where((room) => room.isE2EE)
        .toList();

    Log.i(
      'Retrying decryption across ${encryptedRooms.length} encrypted rooms',
    );

    for (final room in encryptedRooms) {
      try {
        if (loadMissingTimelines && room.timeline == null) {
          await room.getTimeline().timeout(const Duration(seconds: 8));
        }

        await room.retryDecryptAll();
        await Future<void>.delayed(const Duration(milliseconds: 40));
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content:
              'Failed to retry decrypt for encrypted room '
              'room=${_matrixLogHash(room.identifier)}',
        );
      }
    }
  }

  Future<void> repairSessionAfterUnknownToken() async {
    if (!BuildConfig.WEB || !_matrixClient.isLogged()) {
      return;
    }

    if (_verificationInProgress) {
      Log.i(
        'Skipping Matrix unknown-token repair because key verification is in progress',
      );
      return;
    }

    await _runSerializedSessionRepair(
      waitLog:
          'Waiting for the current Matrix session repair before handling M_UNKNOWN_TOKEN',
      skipLog:
          'Skipping Matrix unknown-token repair because a repair was attempted recently',
      startLog: 'Repairing the Matrix session after M_UNKNOWN_TOKEN',
      minInterval: const Duration(seconds: 5),
      action: () async {
        try {
          await _matrixClient.refreshAccessToken();
        } catch (error) {
          Log.w(
            'Unable to proactively refresh the Matrix access token during '
            'M_UNKNOWN_TOKEN repair error=${_matrixLogError(error)}',
          );
        }

        await _matrixClient.ensureNotSoftLoggedOut(const Duration(minutes: 30));
        await _matrixClient.oneShotSync(timeout: const Duration(seconds: 10));
        _updateRoomslist();
        _updateSpacesList();
        await persistDeviceProfile();
        await _ensureSsssAndCrossSigningCached();
      },
    );
  }

  Future<T> runWithSessionRepairOnUnknownToken<T>(
    String operation,
    Future<T> Function() action, {
    bool aggressiveRepair = true,
  }) async {
    final safeOperation = Log.redactSensitiveInfo(operation);
    if (BuildConfig.WEB) {
      final inFlightRepair =
          _softLogoutRefreshInFlight ?? _sessionRepairInFlight;
      if (inFlightRepair != null) {
        Log.i(
          'Waiting for the current Matrix session repair before $safeOperation',
        );
        await inFlightRepair;
      }
    }

    try {
      return await action();
    } on matrix.MatrixException catch (error) {
      if (!BuildConfig.WEB ||
          !_matrixClient.isLogged() ||
          error.error != matrix.MatrixError.M_UNKNOWN_TOKEN) {
        rethrow;
      }

      Log.w(
        'Matrix operation $safeOperation hit M_UNKNOWN_TOKEN. Attempting session repair and retrying once.',
      );
      MatrixSessionAudit.record(
        'Matrix operation $safeOperation hit M_UNKNOWN_TOKEN for '
        'client=${_matrixLogHash(_id)}. Running session repair before retrying.',
      );

      try {
        if (aggressiveRepair) {
          await repairSessionAfterUnknownToken();
        } else {
          await refreshSessionAfterResume(aggressive: false);
        }
      } catch (repairError, repairTrace) {
        Log.onError(
          repairError,
          repairTrace,
          content:
              'Failed to repair Matrix session while retrying $safeOperation '
              'after M_UNKNOWN_TOKEN',
        );
        rethrow;
      }

      try {
        return await action();
      } on matrix.MatrixException catch (retryError, retryTrace) {
        if (retryError.error == matrix.MatrixError.M_UNKNOWN_TOKEN) {
          Log.onError(
            retryError,
            retryTrace,
            content:
                'Matrix operation $safeOperation still returned '
                'M_UNKNOWN_TOKEN after session repair retry',
          );
        }
        rethrow;
      }
    }
  }

  @override
  Future<void> logout() {
    preferences.removeRegisteredMatrixClient(_matrixClient.clientName);
    if (BuildConfig.WEB) {
      unawaited(
        preferences.removeMatrixDeviceProfilesForClient(
          _matrixClient.clientName,
        ),
      );
      unawaited(MatrixClientRegistry.remove(_matrixClient.clientName));
      unawaited(
        _clearWebSessionBootstrapStateIfOwner(_matrixClient.clientName),
      );
    }
    return _matrixClient.logout();
  }

  Future<void> _postLoginSuccess() async {
    await init(false);

    if (BuildConfig.WEB && !_matrixClient.encryptionEnabled) {
      MatrixSessionAudit.record(
        'Matrix login completed for client=${_matrixLogHash(_id)}, but '
        'encryption is still unavailable in the active client state.',
      );
    }

    for (var component in getAllComponents()!) {
      if (component is NeedsPostLoginInit) {
        try {
          (component as NeedsPostLoginInit).postLoginInit();
        } catch (error, trace) {
          // One failing component must not abort the remaining post-login
          // inits or trip the login-success fallback that downgrades the
          // freshly loaded self profile.
          Log.onError(
            error,
            trace,
            content:
                'Post-login init failed for component ${component.runtimeType}',
          );
        }
      }
    }
  }

  Future<LoginResult> _completeSuccessfulLogin() async {
    preferences.addRegisteredMatrixClient(identifier);

    try {
      await _postLoginSuccess();
      return LoginResultSuccess();
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content:
            'Post-login Matrix startup failed after the homeserver already accepted the login/session.',
      );

      if (BuildConfig.WEB) {
        MatrixSessionAudit.record(
          'Post-login startup failed after successful Matrix authentication '
          'for client=${_matrixLogHash(_id)} error=${_matrixLogError(error)}',
        );
      }

      if (_matrixClient.isLogged()) {
        // Only fall back to the bare user-id profile when nothing richer has
        // loaded; a late post-login failure must not erase an avatar and
        // display name that _updateOwnProfile already fetched.
        if (self is! MatrixProfile) {
          _setBasicSelfProfileIfLoggedIn();
        }
        if (BuildConfig.WEB) {
          MatrixSessionAudit.record(
            'Preserving the successful Matrix login for '
            'client=${_matrixLogHash(_id)} because the session is already '
            'stored locally even though post-login startup failed.',
          );
        }
        return LoginResultSuccess();
      }

      return LoginResultError(error.toString());
    }
  }

  Future<void> _ensureCurrentDeviceDisplayName() async {
    final updateInFlight = _deviceDisplayNameUpdateInFlight;
    if (updateInFlight != null) {
      await updateInFlight;
      return;
    }

    final updateFuture = _updateCurrentDeviceDisplayName();
    _deviceDisplayNameUpdateInFlight = updateFuture;

    try {
      await updateFuture;
    } finally {
      if (identical(_deviceDisplayNameUpdateInFlight, updateFuture)) {
        _deviceDisplayNameUpdateInFlight = null;
      }
    }
  }

  Future<void> _updateCurrentDeviceDisplayName() async {
    final deviceId = _matrixClient.deviceID;
    if (deviceId == null) {
      return;
    }

    try {
      await _matrixClient.updateDevice(
        deviceId,
        displayName: BuildConfig.matrixDeviceDisplayName,
      );
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Failed to refresh Matrix device display name',
      );
    }
  }

  Future<void> _updateOwnProfile() async {
    final id = _matrixClient.userID;
    if (id == null) {
      return;
    }

    // Never leave a successfully logged-in session presenting itself as the
    // generic ErrorProfile just because the richer profile lookup is still
    // loading or failed transiently.
    _setBasicSelfProfileIfLoggedIn();

    try {
      var data = await _matrixClient.database.getUserProfile(id);
      if (data != null) {
        _setSelfProfile(
          MatrixProfile(
            this,
            matrix.Profile(
              userId: id,
              displayName: data.displayname,
              avatarUrl: data.avatarUrl,
            ),
          ),
        );

        // Update own profile, but lets not wait for it before continuing.
        _matrixClient
            .getProfileFromUserId(id)
            .then((profile) {
              _setSelfProfile(MatrixProfile(this, profile));
            })
            .catchError((error, trace) {
              Log.onError(
                error,
                trace,
                content: 'Failed to refresh the cached Matrix self profile',
              );
            });
      } else {
        _setSelfProfile(
          MatrixProfile(this, await _matrixClient.getProfileFromUserId(id)),
        );
      }
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content:
            'Failed to update the Matrix self profile during client startup',
      );
    }
  }

  Future<void> _refreshOwnProfileFromServer() async {
    final id = _matrixClient.userID;
    if (id == null) {
      return;
    }

    try {
      _setSelfProfile(
        MatrixProfile(this, await _matrixClient.getProfileFromUserId(id)),
      );
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Failed to refresh the Matrix self profile from the server',
      );
    }
  }

  bool _setBasicSelfProfileIfLoggedIn() {
    final id = _matrixClient.userID;
    if (!_matrixClient.isLogged() || id == null) {
      return false;
    }

    _setSelfProfile(
      MatrixProfile(this, matrix.Profile(userId: id, displayName: id)),
    );
    return true;
  }

  void _setSelfProfile(Profile profile) {
    if (_isClosed) {
      return;
    }

    self = profile;
    if (_onSelfUpdated.isClosed) {
      return;
    }
    _onSelfUpdated.add(null);
  }

  void _setLocalSelfProfile({String? displayName, Uri? avatarUrl}) {
    final id = _matrixClient.userID;
    if (id == null) {
      return;
    }

    final current = self;
    final currentMatrixProfile = current is MatrixProfile ? current : null;
    final fields = Map<String, dynamic>.from(
      currentMatrixProfile?.fields ?? const <String, dynamic>{},
    );
    if (displayName != null) {
      fields['displayname'] = displayName;
    }
    if (avatarUrl != null) {
      fields['avatar_url'] = avatarUrl.toString();
    }
    _setSelfProfile(
      MatrixProfile(
        this,
        matrix.Profile(
          userId: id,
          displayName:
              displayName ??
              currentMatrixProfile?.profile.displayName ??
              current?.displayName ??
              id,
          avatarUrl: avatarUrl ?? currentMatrixProfile?.profile.avatarUrl,
        ),
        fields: fields,
      ),
    );
  }

  void _updateRoomslist() {
    var joinedRooms = _matrixClient.rooms.where(
      (element) => !element.isSpace && element.membership.isJoin,
    );

    for (var room in joinedRooms) {
      if (hasRoom(room.id)) continue;
      rooms.add(MatrixRoom(this, room, _matrixClient));
    }

    rooms.removeWhere((e) => !joinedRooms.any((r) => r.id == e.identifier));
  }

  void _updateSpacesList() {
    var allSpaces = _matrixClient.rooms.where(
      (element) =>
          element.isSpace && element.membership == matrix.Membership.join,
    );

    bool didChange = false;
    for (var space in allSpaces) {
      if (hasSpace(space.id)) continue;
      spaces.add(MatrixSpace(this, space, _matrixClient));
      didChange = true;
    }

    if (didChange) {
      for (var space in spaces) {
        (space as MatrixSpace).updateRoomsList();
      }
    }
  }

  @override
  Future<Room> createRoom(CreateRoomArgs args) async {
    var creationContent = null;
    Map<String, Object?>? powerLevelAdditions = {};

    List<matrix.StateEvent>? initialState;
    if (args.roomType == RoomType.photoAlbum) {
      creationContent = {"type": "chat.commet.photo_album"};
    }

    if (args.roomType == RoomType.voipRoom) {
      creationContent = {"type": "org.matrix.msc3417.call"};
      powerLevelAdditions = {
        "events": {
          "org.matrix.msc3401.call": 0,
          "org.matrix.msc3401.call.member": 0,
        },
      };
    }

    if (args.roomType == RoomType.forum) {
      creationContent = {"type": "chat.intergalactic.app.forum"};
    }

    if (args.roomType == RoomType.calendar) {
      const widgetId = "chat.commet.room_calendar";
      var widgetHost = GlobalConfig.calendarWidgetHost;
      creationContent = {"type": "chat.commet.calendar"};
      initialState = [
        matrix.StateEvent(
          content: {
            "type": "chat.commet.widgets.calendar",
            "url":
                "https://${widgetHost}/#/?widgetId=\$matrix_widget_id&userId=\$matrix_user_id&theme=\$org.matrix.msc2873.client_theme&userDisplayName=\$matrix_display_name&userAvatarUrl=\$matrix_avatar_url&language=\$org.matrix.msc2873.client_language",
            "name": "Calendar",
            "data": {},
          },
          type: "im.vector.modular.widgets",
          stateKey: widgetId,
        ),
        matrix.StateEvent(
          content: {
            "widgets": {
              widgetId: {
                "container": "top",
                "height": 100,
                "width": 100,
                "index": 0,
              },
            },
          },
          type: "io.element.widgets.layout",
        ),
      ];
    }

    var visibility = switch (args.visibility) {
      final RoomVisibilityPrivate _ => matrix.Visibility.private,
      final RoomVisibilityPublic _ => matrix.Visibility.public,
      final RoomVisibilityKnock _ => matrix.Visibility.private,
      final RoomVisibilityRestricted _ => null,
      final RoomVisibilityKnockRestricted _ => null,
      _ => matrix.Visibility.private,
    };

    final allowedSpaces = switch (args.visibility) {
      final RoomVisibilityRestricted restricted => restricted.spaces,
      final RoomVisibilityKnockRestricted restricted => restricted.spaces,
      _ => const <String>[],
    };

    final joinRulesContent = switch (args.visibility) {
      final RoomVisibilityKnock _ ||
      final RoomVisibilityRestricted _ ||
      final RoomVisibilityKnockRestricted _ =>
        MatrixRoom.joinRulesContentForVisibility(args.visibility!),
      _ => null,
    };

    if (allowedSpaces.isNotEmpty || joinRulesContent != null) {
      initialState ??= List.empty(growable: true);

      initialState = [
        ...initialState,
        for (var i in allowedSpaces)
          matrix.StateEvent(
            stateKey: i,
            type: matrix.EventTypes.SpaceParent,
            content: {
              "canonical": true,
              "via": [
                if (self?.identifier.domain != null) self?.identifier.domain,
              ],
            },
          ),
        if (joinRulesContent != null)
          matrix.StateEvent(
            content: joinRulesContent,
            type: matrix.EventTypes.RoomJoinRules,
          ),
      ];
    }

    var id = await _matrixClient.createRoom(
      creationContent: creationContent,
      name: args.name,
      initialState: initialState,
      topic: args.topic,
      visibility: visibility,
    );

    await _matrixClient.waitForRoomInSync(id);

    var matrixRoom = _matrixClient.getRoomById(id)!;
    if (args.enableE2EE!) {
      await matrixRoom.enableEncryption();
    }

    if (powerLevelAdditions.isNotEmpty) {
      var events = await matrixClient.getRoomState(id);

      var currentPerms = events
          .firstWhereOrNull((i) => i.type == matrix.EventTypes.RoomPowerLevels)
          ?.content;

      if (currentPerms != null) {
        var newPerms = <String, dynamic>{
          ...currentPerms,
          "events": <String, dynamic>{
            ...?currentPerms["events"] as Map<String, dynamic>?,
            ...?powerLevelAdditions["events"] as Map<String, dynamic>?,
          },
        };
        _matrixClient.setRoomStateWithKey(
          id,
          matrix.EventTypes.RoomPowerLevels,
          "",
          newPerms,
        );
      }
    }

    if (hasRoom(id)) return getRoom(id)!;
    var room = MatrixRoom(this, matrixRoom, _matrixClient);
    rooms.add(room);
    return room;
  }

  @override
  Future<Space> createSpace(CreateRoomArgs args) async {
    var id = await _matrixClient.createSpace(
      name: args.name,
      waitForSync: true,
      visibility: args.visibility is RoomVisibilityPublic
          ? matrix.Visibility.public
          : matrix.Visibility.private,
    );

    final joinRulesContent = switch (args.visibility) {
      final RoomVisibilityKnock _ ||
      final RoomVisibilityRestricted _ ||
      final RoomVisibilityKnockRestricted _ =>
        MatrixRoom.joinRulesContentForVisibility(args.visibility!),
      _ => null,
    };

    if (joinRulesContent != null) {
      await _matrixClient.setRoomStateWithKey(
        id,
        matrix.EventTypes.RoomJoinRules,
        "",
        joinRulesContent,
      );
    }

    await _allowMemberSoundboardUploads(id);

    if (hasSpace(id)) return getSpace(id)!;
    var space = MatrixSpace(
      this,
      _matrixClient.getRoomById(id)!,
      _matrixClient,
    );
    spaces.add(space);
    return space;
  }

  Future<void> _allowMemberSoundboardUploads(String spaceId) async {
    try {
      var events = await matrixClient.getRoomState(spaceId);
      var currentPerms = events
          .firstWhereOrNull((i) => i.type == matrix.EventTypes.RoomPowerLevels)
          ?.content;
      if (currentPerms == null) {
        return;
      }

      final currentEvents = Map<String, dynamic>.from(
        currentPerms["events"] is Map
            ? currentPerms["events"] as Map
            : const {},
      );
      if (currentEvents[SoundboardEventTypes.soundState] == 0) {
        return;
      }

      final newPerms = <String, dynamic>{
        ...currentPerms,
        "events": <String, dynamic>{
          ...currentEvents,
          SoundboardEventTypes.soundState: 0,
        },
      };
      await _matrixClient.setRoomStateWithKey(
        spaceId,
        matrix.EventTypes.RoomPowerLevels,
        "",
        newPerms,
      );
      await _matrixClient.waitForRoomInSync(spaceId);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to enable default member soundboard uploads for $spaceId',
      );
    }
  }

  @override
  Future<Space> joinSpace(String address) async {
    var info = parseAddressToIdAndVia(address);
    if (info == null) {
      throw Exception("Invalid address");
    }
    var id = await _matrixClient.joinRoom(info.$1, via: info.$2);
    await _matrixClient.waitForRoomInSync(id);
    if (hasSpace(id)) return getSpace(id)!;

    var space = MatrixSpace(
      this,
      _matrixClient.getRoomById(id)!,
      _matrixClient,
    );
    spaces.add(space);
    return space;
  }

  @override
  Future<Room> joinRoom(String address) async {
    var info = parseAddressToIdAndVia(address);
    if (info == null) {
      throw Exception("Invalid address");
    }

    var id = await _matrixClient.joinRoom(info.$1, via: info.$2);
    await _matrixClient.waitForRoomInSync(id);
    if (hasRoom(id)) return getRoom(id)!;

    var room = MatrixRoom(this, _matrixClient.getRoomById(id)!, _matrixClient);
    rooms.add(room);
    return room;
  }

  /// Every call-ending step [close] runs before anything else it tears down.
  ///
  /// The direct calls, plus the call component of every room that has one.
  /// Room close deliberately skips that component so a call can outlive the
  /// room view for picture-in-picture and backgrounding - which is correct for
  /// the room and exactly why client close must reach it here: nothing else
  /// ever will, and it is the only owner of a room's LiveKit call and of any
  /// join still in flight. Disposing it ends the call, and makes a join that
  /// lands later end the session it produced.
  ///
  /// Static and separate from [close] because a MatrixClient cannot be built in
  /// a unit test, and which sessions close reaches is the part worth pinning.
  @visibleForTesting
  static List<Future<void> Function()> callTeardownsForClose({
    required MatrixVoipComponent? directCalls,
    required Iterable<Room> rooms,
  }) {
    return [
      if (directCalls != null) directCalls.hangUpCalls,
      for (final room in rooms)
        if (room.getComponent<VoipRoomComponent>()
            case final DisposableComponent voipRoom)
          voipRoom.dispose,
    ];
  }

  @override
  Future<void> close() async {
    // Calls first, while the client can still send their hang-ups and clear
    // their memberships - before the flag, the subscriptions and the SDK
    // client they depend on go. One bound covers all of them together, so a
    // client with several calls waits no longer than a client with one.
    await hangUpBeforeClientClose(
      callTeardownsForClose(
        directCalls: getComponent<MatrixVoipComponent>(),
        rooms: rooms.toList(growable: false),
      ),
      context: 'client close',
      bound: clientCloseHangUpBound,
    );

    _isClosed = true;
    await _roomNotificationSnoozes.dispose();
    _matrixSdkInitialized = false;
    _matrixSdkInitInFlight = null;
    await _cancelOwnedMatrixSubscriptions();
    await _closeOwnedStreamControllers();

    for (final component in componentsInternal) {
      if (component is! DisposableComponent) {
        continue;
      }

      try {
        await (component as DisposableComponent).dispose();
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content: 'Failed to dispose Matrix component before client close',
        );
      }
    }

    final httpClient = _matrixClient.httpClient;
    try {
      await _matrixClient.dispose();
    } finally {
      httpClient.close();
      await _cancelOwnedMatrixSubscriptions();
      await _closeOwnedStreamControllers();
    }
  }

  Future<void> _cancelOwnedMatrixSubscriptions() async {
    final matrixSyncSubscription = _matrixSyncSubscription;
    _matrixSyncSubscription = null;
    if (matrixSyncSubscription != null) {
      try {
        await matrixSyncSubscription.cancel();
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content: 'Failed to cancel Matrix sync subscription',
        );
      }
    }

    final syncStatusSubscription = _syncStatusSubscription;
    _syncStatusSubscription = null;
    if (syncStatusSubscription != null) {
      try {
        await syncStatusSubscription.cancel();
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content: 'Failed to cancel Matrix sync status subscription',
        );
      }
    }

    try {
      await _e2eeDiagnostics.dispose();
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Failed to dispose Matrix E2EE diagnostics',
        category: LogCategory.matrix,
        source: 'matrix-e2ee',
      );
    }
  }

  Future<void> _closeOwnedStreamControllers() async {
    if (!_onSync.isClosed) {
      try {
        await _onSync.close();
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content: 'Failed to close Matrix sync stream controller',
        );
      }
    }

    if (!_onSelfUpdated.isClosed) {
      try {
        await _onSelfUpdated.close();
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content: 'Failed to close Matrix self-profile stream controller',
        );
      }
    }

    if (!connectionStatusChanged.isClosed) {
      try {
        await connectionStatusChanged.close();
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content: 'Failed to close Matrix connection status controller',
        );
      }
    }
  }

  @override
  Future<void> setAvatar(Uint8List bytes, String mimeType) async {
    final userId = _matrixClient.userID;
    if (userId == null) {
      return;
    }

    final avatarUri = await _matrixClient.uploadContent(
      bytes,
      filename: 'avatar',
      contentType: mimeType.isEmpty ? null : mimeType,
    );
    await _matrixClient.setProfileField(userId, 'avatar_url', {
      'avatar_url': avatarUri.toString(),
    });
    _setLocalSelfProfile(displayName: self?.displayName, avatarUrl: avatarUri);
    await _refreshOwnProfileFromServer();
  }

  @override
  Future<void> setDisplayName(String name) async {
    final userId = _matrixClient.userID;
    if (userId == null) {
      return;
    }

    await _matrixClient.setProfileField(userId, "displayname", {
      "displayname": name,
    });
    _setLocalSelfProfile(displayName: name);
    await _refreshOwnProfileFromServer();
  }

  @override
  Iterable<Room> getEligibleRoomsForSpace(Space space) {
    return rooms.where((room) => !space.containsRoom(room.identifier));
  }

  @override
  Widget buildDebugInfo() {
    var data = _matrixClient.accountData.copy();

    return SelectionArea(
      child: Codeblock(
        language: "json",
        text: const JsonEncoder.withIndent('  ').convert(data),
      ),
    );
  }

  @override
  Room? getRoom(String identifier) {
    return _rooms.tryFirstWhere((element) => element.identifier == identifier);
  }

  @override
  Space? getSpace(String identifier) {
    return _spaces.tryFirstWhere((element) => element.identifier == identifier);
  }

  @override
  bool hasPeer(String identifier) {
    return _peersMap.containsKey(identifier);
  }

  @override
  bool hasRoom(String identifier) {
    return _rooms.any((element) => element.identifier == identifier);
  }

  @override
  bool hasSpace(String identifier) {
    return _spaces.any((element) => element.identifier == identifier);
  }

  (String, List<String>?)? parseAddressToIdAndVia(String address) {
    String id = address;
    List<String>? via;

    if (address.startsWith("!") || address.startsWith("#")) {
      var split = address.split("?");
      id = split.first;

      if (split.length >= 2) {
        var query = Uri.splitQueryString(split[1]);
        if (query.containsKey("via")) {
          via = query["via"]!.split(",");
        }

        // dont need to use via when it is the homeserver this user is connected to
        via?.removeWhere((i) => i == matrixClient.userID!.domain);
      }
    }

    if (address.startsWith("https")) {
      var url = Uri.parse(address);
      var info = parseMatrixLink(url);

      if (info == null) {
        return null;
      }

      return parseAddressToIdAndVia(info.$3);
    }

    return (id, via);
  }

  @override
  Future<RoomPreview?> getRoomPreview(String address) async {
    try {
      var info = parseAddressToIdAndVia(address);
      if (info == null) return null;

      return await _matrixClient.getRoomPreview(info.$1, via: info.$2);
    } catch (exception, trace) {
      Log.onError(exception, trace);
      return null;
    }
  }

  @override
  Future<RoomPreview?> getSpacePreview(String address) async {
    return getRoomPreview(address);
  }

  @override
  T? getComponent<T extends Component>() {
    for (var component in componentsInternal) {
      if (component is T) return component as T;
    }

    return null;
  }

  @override
  List<T>? getAllComponents<T extends Component<Client>>() {
    List<T> components = List.empty(growable: true);
    for (var component in componentsInternal) {
      if (component is T) {
        components.add(component as T);
      }
    }

    return components;
  }

  @override
  Future<void> leaveRoom(Room room) async {
    await _matrixClient.leaveRoom(room.identifier);
    await _matrixClient.waitForRoomInSync(room.identifier);
    await room.close();
    _rooms.remove(room);
  }

  @override
  Future<void> leaveSpace(Space space) async {
    await _matrixClient.leaveRoom(space.identifier);
    await _matrixClient.waitForRoomInSync(space.identifier);
    await space.close();
    _spaces.remove(space);
  }

  void onSyncStatusChanged(matrix.SyncStatusUpdate event) {
    if (_isClosed || connectionStatusChanged.isClosed) {
      return;
    }

    ClientConnectionStatus value = ClientConnectionStatus.unknown;

    var connected =
        _matrixClient.onSync.value != null &&
        event.status != matrix.SyncStatus.error &&
        _matrixClient.prevBatch != null;

    if (connected) {
      value = ClientConnectionStatus.connected;
    } else {
      value = switch (event.status) {
        matrix.SyncStatus.waitingForResponse =>
          ClientConnectionStatus.connecting,
        matrix.SyncStatus.processing => ClientConnectionStatus.connecting,
        matrix.SyncStatus.cleaningUp => ClientConnectionStatus.connecting,
        matrix.SyncStatus.finished => ClientConnectionStatus.connected,
        matrix.SyncStatus.error => ClientConnectionStatus.disconnected,
      };
    }

    var result = ClientConnectionStatusUpdate(value);
    result.progress = event.progress;

    connectionStatusChanged.add(result);
  }

  @override
  Future<(bool, List<LoginFlow>?)> setHomeserver(Uri uri) async {
    try {
      var result = await _matrixClient.checkHomeserver(uri);

      var flows = result.$3;

      var resultFlows = List<LoginFlow>.empty(growable: true);

      if (flows.any((element) => element.type == "m.login.password")) {
        resultFlows.add(MatrixPasswordLoginFlow());
      }

      if (flows.any((element) => element.type == "m.login.sso")) {
        resultFlows.addAll(await _getSsoFlows());
      }

      return (true, resultFlows);
    } catch (error, trace) {
      Log.onError(error, trace);
      return (false, null);
    }
  }

  Future<List<LoginFlow>> _getSsoFlows() async {
    List<LoginFlow> result = List.empty(growable: true);

    Map<String, dynamic> flows = await _matrixClient.request(
      matrix.RequestType.GET,
      "/client/v3/login",
    );

    flows["flows"].where((element) => element['type'] == "m.login.sso").forEach(
      (element) {
        element["identity_providers"]?.forEach((provider) {
          result.add(MatrixSSOLoginFlow.fromJson(this, provider));
        });
      },
    );

    if (result.isEmpty) {
      result.add(MatrixSSOLoginFlow(name: "homeserver", id: null));
    }

    return result;
  }

  @override
  Future<LoginResult> executeLoginFlow(LoginFlow flow) async {
    var result = await flow.submit(this);

    if (result is LoginResultSuccess) {
      return _completeSuccessfulLogin();
    }

    return result;
  }

  @override
  Future<LoginResult> registerAccount({
    required String username,
    required String password,
    String? registrationToken,
    String? registrationSession,
  }) async {
    final token = registrationToken?.trim();
    final hasToken = token != null && token.isNotEmpty;

    try {
      await _submitRegistration(
        username: username,
        password: password,
        auth: hasToken
            ? _RegistrationTokenAuth(token: token, session: registrationSession)
            : null,
      );
    } on matrix.MatrixException catch (e) {
      if (_shouldTryDummyRegistrationAuth(e)) {
        try {
          await _submitRegistration(
            username: username,
            password: password,
            auth: _DummyRegistrationAuth(session: e.session),
          );
          return _completeSuccessfulLogin();
        } on matrix.MatrixException catch (e2) {
          return LoginResultError(e2.errorMessage);
        } catch (e2) {
          return LoginResultError(e2.toString());
        }
      } else if (_registrationRequiresToken(e)) {
        if (!hasToken) {
          return LoginResultRegistrationTokenRequired(
            session: e.session,
            message: _registrationTokenPromptMessage(e),
          );
        }

        if (registrationSession == null && e.session != null) {
          return registerAccount(
            username: username,
            password: password,
            registrationToken: token,
            registrationSession: e.session,
          );
        }

        return LoginResultError(e.errorMessage);
      } else if (!hasToken && _mentionsRegistrationToken(e)) {
        return LoginResultRegistrationTokenRequired(
          session: e.session,
          message: _registrationTokenPromptMessage(e),
        );
      }

      return LoginResultError(e.errorMessage);
    } catch (e) {
      return LoginResultError(e.toString());
    }

    // Registration succeeded without additional UIA stages.
    return _completeSuccessfulLogin();
  }

  Future<void> _submitRegistration({
    required String username,
    required String password,
    required matrix.AuthenticationData? auth,
  }) async {
    await _matrixClient.register(
      username: username,
      password: password,
      initialDeviceDisplayName: BuildConfig.matrixDeviceDisplayName,
      auth: auth,
    );
  }

  bool _shouldTryDummyRegistrationAuth(matrix.MatrixException exception) {
    if (!_registrationRequiresDummy(exception)) return false;
    return !_registrationRequiresToken(exception) ||
        exception.completedAuthenticationFlows.contains(
          _registrationTokenAuthType,
        );
  }

  bool _registrationRequiresToken(matrix.MatrixException exception) {
    return exception.authenticationFlows?.any(
          (flow) => flow.stages.contains(_registrationTokenAuthType),
        ) ==
        true;
  }

  bool _registrationRequiresDummy(matrix.MatrixException exception) {
    return exception.authenticationFlows?.any(
          (flow) => flow.stages.contains(_dummyAuthType),
        ) ==
        true;
  }

  bool _mentionsRegistrationToken(matrix.MatrixException exception) {
    final message = exception.errorMessage.toLowerCase();
    return message.contains('registration token') ||
        message.contains('invite code');
  }

  String _registrationTokenPromptMessage(matrix.MatrixException exception) {
    final message = exception.errorMessage.trim();
    if (message.isNotEmpty &&
        message.toLowerCase() != 'require additional authentication') {
      return message;
    }

    return 'This server requires an invite code to create an account.';
  }

  static (MatrixLinkType, String, String)? parseMatrixLink(Uri uri) {
    if (uri.authority != "matrix.to") {
      return null;
    }

    var joinUrl = Uri.decodeComponent(uri.fragment.substring(1));

    var roomId = joinUrl.split("?").first;

    if (roomId.startsWith("@")) {
      return (MatrixLinkType.user, roomId, joinUrl);
    }

    if (roomId.startsWith("!")) {
      return (MatrixLinkType.room, roomId, joinUrl);
    }

    if (roomId.startsWith("#")) {
      return (MatrixLinkType.roomAlias, roomId, joinUrl);
    }

    return null;
  }

  @override
  Room? getRoomByAlias(String identifier) {
    return rooms.firstWhereOrNull((r) {
      var room = r as MatrixRoom;

      var state = room.matrixRoom.getState("m.room.canonical_alias");
      if (state == null) return false;

      if (state.content["alias"] == identifier) {
        return true;
      }

      var alts = state.content["alt_aliases"];
      if (alts is List<dynamic>) {
        return alts.contains(identifier);
      }

      return false;
    });
  }

  Future<void> recordOutstandingKnock(String roomId) async {
    await preferences.addKnockedRoomId(identifier, roomId);
    Log.i(
      'Recorded outstanding knock for auto-accept '
      'room=${MatrixClient.hash(roomId).substring(0, 12)} '
      'client=${MatrixClient.hash(identifier).substring(0, 12)}',
      category: LogCategory.matrix,
      source: 'invitation-auto-accept',
    );
  }

  @override
  Future<RoomPreviewJoinResult> joinRoomFromPreview(RoomPreview preview) async {
    return joinRoomFromPreviewWithMatrixActions(
      preview: preview,
      parseAddressToIdAndVia: parseAddressToIdAndVia,
      knockRoom: (roomId, {via}) async {
        await _matrixClient.knockRoom(roomId, via: via);
        await recordOutstandingKnock(roomId);
      },
      joinRoom: _matrixClient.joinRoom,
      waitForRoomInSync: _matrixClient.waitForRoomInSync,
      hasRoom: hasRoom,
      getRoom: getRoom,
      createJoinedRoom: (id) {
        final room = MatrixRoom(
          this,
          _matrixClient.getRoomById(id)!,
          _matrixClient,
        );
        rooms.add(room);
        return room;
      },
    );
  }
}

typedef MatrixPreviewAddressParser =
    (String, List<String>?)? Function(String address);
typedef MatrixPreviewKnockRoom =
    Future<void> Function(String roomId, {List<String>? via});
typedef MatrixPreviewJoinRoom =
    Future<String> Function(String roomId, {List<String>? via});
typedef MatrixPreviewWaitForRoomInSync = Future<void> Function(String roomId);
typedef MatrixPreviewHasRoom = bool Function(String roomId);
typedef MatrixPreviewGetRoom = Room? Function(String roomId);
typedef MatrixPreviewCreateJoinedRoom = Room Function(String roomId);

@visibleForTesting
Future<RoomPreviewJoinResult> joinRoomFromPreviewWithMatrixActions({
  required RoomPreview preview,
  required MatrixPreviewAddressParser parseAddressToIdAndVia,
  required MatrixPreviewKnockRoom knockRoom,
  required MatrixPreviewJoinRoom joinRoom,
  required MatrixPreviewWaitForRoomInSync waitForRoomInSync,
  required MatrixPreviewHasRoom hasRoom,
  required MatrixPreviewGetRoom getRoom,
  required MatrixPreviewCreateJoinedRoom createJoinedRoom,
}) async {
  final address = matrixAddressForRoomPreview(preview);
  final info = parseAddressToIdAndVia(address);
  if (info == null) {
    throw Exception("Invalid address");
  }

  if (matrixPreviewRequiresKnock(preview)) {
    await knockRoom(info.$1, via: info.$2);
    return const RoomPreviewJoinResult.knockRequested();
  }

  final id = await joinRoom(info.$1, via: info.$2);
  await waitForRoomInSync(id);
  if (hasRoom(id)) {
    return RoomPreviewJoinResult.joined(getRoom(id)!);
  }

  return RoomPreviewJoinResult.joined(createJoinedRoom(id));
}

@visibleForTesting
String matrixAddressForRoomPreview(RoomPreview preview) {
  if (preview is MatrixSpaceRoomChunkPreview && preview.via.isNotEmpty) {
    return '${preview.roomId}?via=${preview.via.join(",")}';
  }
  return preview.roomId;
}

@visibleForTesting
bool matrixPreviewRequiresKnock(RoomPreview preview) {
  final visibility = preview.visibility;
  return visibility is RoomVisibilityKnock ||
      visibility is RoomVisibilityKnockRestricted;
}

enum MatrixLinkType { room, roomAlias, user }

const _registrationTokenAuthType = 'm.login.registration_token';
const _dummyAuthType = 'm.login.dummy';

/// Custom [AuthenticationData] for Synapse MSC3231 registration tokens.
///
/// Serialises as:
/// ```json
/// {"type": "m.login.registration_token", "session": "...", "token": "..."}
/// ```
class _RegistrationTokenAuth extends matrix.AuthenticationData {
  final String token;

  _RegistrationTokenAuth({required this.token, String? session})
    : super(type: _registrationTokenAuthType, session: session);

  @override
  Map<String, Object?> toJson() {
    final data = super.toJson();
    data['token'] = token;
    return data;
  }
}

class _DummyRegistrationAuth extends matrix.AuthenticationData {
  _DummyRegistrationAuth({String? session})
    : super(type: _dummyAuthType, session: session);
}

/// Whether a sync carries the account-data event that push rules are derived
/// from.
///
/// `Client.globalPushRules` reads `m.push_rules` out of global account data, so
/// this event arriving is exactly the moment every cached room and space
/// push-rule state may be wrong. Gating on it keeps a normal sync from
/// re-reading the rule list for every room and space.
@visibleForTesting
bool syncCarriesPushRules(matrix.SyncUpdate update) =>
    update.accountData?.any((event) => event.type == 'm.push_rules') ?? false;
