import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_lifecycle_watcher.dart';
import 'package:intergalactic/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:intergalactic/client/matrix/components/typing_indicators/matrix_typing_indicators_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/in_memory_cache.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';
import 'package:matrix/matrix.dart';

class MatrixUserPresenceComponent
    implements UserPresenceComponent<MatrixClient>, DisposableComponent {
  static const _presenceRateLimitPadding = Duration(milliseconds: 750);

  @override
  MatrixClient client;

  final StreamController<(String, UserPresence)> _controller =
      StreamController.broadcast();
  final List<StreamSubscription> _subscriptions = [];
  String? _lastPresenceFailureKey;
  DateTime? _lastPresenceFailureLogAt;
  DateTime? _presenceRetryAfter;
  bool _loggedPresenceRateLimitSkip = false;
  bool _disposed = false;
  final Map<String, DateTime> _lastServerPresenceRefresh = {};
  final Map<String, Future<CachedPresence?>> _serverPresenceRefreshes = {};

  late final InMemoryCache<DateTime> lastSeen;

  MatrixUserPresenceComponent(this.client) {
    lastSeen = InMemoryCache(
      maxRetention: Duration(minutes: 2),
      pollFrequency: Duration(seconds: 100),
    );
    _subscriptions.addAll([
      client.matrixClient.onPresenceChanged.stream.listen(changed),
      client.matrixClient.onSync.stream.listen(onSync),
      lastSeen.onRemove.listen(onLastSeenRemoved),
    ]);

    UserPresenceLifecycleWatcher().init();
  }

  @override
  bool get usePublicReadReceipts {
    var publicReadReceipts = client
        .matrixClient
        .accountData[MatrixReadReceiptComponent.publicReadReceiptsKey]
        ?.content["enabled"];
    return publicReadReceipts is bool ? publicReadReceipts : true;
  }

  @override
  Future<void> setUsePublicReadReceipts(bool value) async {
    await client.matrixClient.setAccountData(
      client.matrixClient.userID!,
      MatrixReadReceiptComponent.publicReadReceiptsKey,
      {"enabled": value},
    );
    client.matrixClient.receiptsPublicByDefault = value;
  }

  @override
  bool get typingIndicatorEnabled {
    var publicTypingIndicator = client
        .matrixClient
        .accountData[MatrixTypingIndicatorsComponent.publicTypingIndicatorKey]
        ?.content["enabled"];
    return publicTypingIndicator is bool ? publicTypingIndicator : true;
  }

  @override
  Future<void> setTypingIndicatorEnabled(bool value) async =>
      await client.matrixClient.setAccountData(
        client.matrixClient.userID!,
        MatrixTypingIndicatorsComponent.publicTypingIndicatorKey,
        {"enabled": value},
      );

  @override
  Future<UserPresence> getUserPresence(String userId) async {
    if (_disposed) {
      return UserPresence(UserPresenceStatus.unknown);
    }

    // Consumer-driven, so it can run at wake before the release trigger has
    // re-established the account database (B5); the read below throws by
    // design against a released connection. Wait on the trigger's gate,
    // which is already complete when nothing was released.
    if (!await DatabaseReleaseTrigger.waitForDatabase('presence.get') ||
        _disposed) {
      return UserPresence(UserPresenceStatus.unknown);
    }

    var presence = await client.matrixClient.fetchCurrentPresence(userId);
    presence = await _refreshCachedPresenceIfNeeded(userId, presence);

    final statusMessage = presence.statusMsg?.trim();
    if (presence.presence == PresenceType.offline &&
        (statusMessage == null || statusMessage.isEmpty) &&
        presence.lastActiveTimestamp == null) {
      var seen = lastSeen.get(userId);
      if (seen != null) {
        if (DateTime.now().difference(seen).inSeconds < 120) {
          return UserPresence(UserPresenceStatus.online);
        }
      }
    }

    return convertPresence(presence);
  }

  Future<CachedPresence> _refreshCachedPresenceIfNeeded(
    String userId,
    CachedPresence cachedPresence,
  ) async {
    if (_disposed) {
      return cachedPresence;
    }

    final now = DateTime.now();
    if (!matrixPresenceShouldRefreshCachedPresence(
      statusMsg: cachedPresence.statusMsg,
      lastRefresh: _lastServerPresenceRefresh[userId],
      now: now,
    )) {
      return cachedPresence;
    }

    final existingRefresh = _serverPresenceRefreshes[userId];
    if (existingRefresh != null) {
      return await existingRefresh ?? cachedPresence;
    }

    final refresh = _refreshPresenceFromServer(userId, cachedPresence);
    _serverPresenceRefreshes[userId] = refresh;
    try {
      return await refresh ?? cachedPresence;
    } finally {
      _serverPresenceRefreshes.remove(userId);
    }
  }

  Future<CachedPresence?> _refreshPresenceFromServer(
    String userId,
    CachedPresence previousPresence,
  ) async {
    if (_disposed) {
      return previousPresence;
    }

    _lastServerPresenceRefresh[userId] = DateTime.now();
    try {
      final response = await client.matrixClient.getPresence(userId);
      final refreshed = await _rememberPresence(
        userId,
        response.presence,
        statusMsg: response.statusMsg,
        lastActiveAgo: response.lastActiveAgo,
        currentlyActive: response.currentlyActive,
      );

      final previousMessage = previousPresence.statusMsg?.trim();
      final refreshedMessage = refreshed.statusMsg?.trim();
      if ((previousMessage == null || previousMessage.isEmpty) &&
          refreshedMessage != null &&
          refreshedMessage.isNotEmpty) {
        Log.d(
          'Matrix presence refreshed blank cached status from server '
          'user=${_matrixPresenceHash(userId)} '
          'status_msg=present status_msg_length=${refreshed.statusMsg!.length}',
          category: LogCategory.matrix,
          source: 'presence',
        );
      }

      return refreshed;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to refresh Matrix presence from server',
        category: LogCategory.matrix,
        source: 'presence',
      );
      return null;
    }
  }

  UserPresence convertPresence(CachedPresence presence) {
    final status = switch (presence.presence) {
      PresenceType.offline => UserPresenceStatus.offline,
      PresenceType.online => UserPresenceStatus.online,
      PresenceType.unavailable => UserPresenceStatus.unavailable,
    };

    UserPresenceMessage? message = null;

    final statusMessage = presence.statusMsg?.trim();
    if (statusMessage != null && statusMessage.isNotEmpty) {
      message = UserPresenceMessage(
        statusMessage,
        PresenceMessageType.userCustom,
      );
    }

    return UserPresence(status, message: message);
  }

  void changed(CachedPresence event) {
    if (_disposed || _controller.isClosed) {
      return;
    }

    _controller.add((event.userid, convertPresence(event)));
  }

  @override
  Stream<(String, UserPresence)> get onPresenceChanged => _controller.stream;

  @override
  Future<void> setStatus(
    UserPresenceStatus status, {
    String? message,
    bool clearMessage = false,
  }) async {
    if (_disposed) {
      return;
    }

    final self = matrixPresenceUserIdForUpdate(
      matrixUserId: client.matrixClient.userID,
      profileUserId: client.self?.identifier,
    );
    if (self == null || self.isEmpty) {
      Log.w(
        'Skipping Matrix presence update because the local user is unavailable',
        category: LogCategory.matrix,
        source: 'presence',
      );
      return;
    }

    final pendingRetryDelay = _remainingPresenceRetryDelay();
    if (pendingRetryDelay != null) {
      if (!_loggedPresenceRateLimitSkip) {
        Log.d(
          'Skipping Matrix presence update until server rate limit resets',
          category: LogCategory.matrix,
          source: 'presence',
        );
        _loggedPresenceRateLimitSkip = true;
      }
      throw UserPresenceRateLimitException(retryAfter: pendingRetryDelay);
    }

    String? currentStatusMessage;
    PresenceType? currentPresenceType;
    int? currentLastActiveAgo;
    bool? currentCurrentlyActive;
    try {
      final current = await _runPresenceNetworkOperation(
        () => client.matrixClient.getPresence(self),
      );
      currentStatusMessage = current.statusMsg;
      currentPresenceType = current.presence;
      currentLastActiveAgo = current.lastActiveAgo;
      currentCurrentlyActive = current.currentlyActive;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to read current Matrix presence before update',
        category: LogCategory.matrix,
        source: 'presence',
      );
    }

    final statusMsg = matrixPresenceStatusMessageForUpdate(
      currentStatusMessage,
      message: message,
      clearMessage: clearMessage,
    );
    final matrixStatus = switch (status) {
      UserPresenceStatus.offline => PresenceType.offline,
      UserPresenceStatus.unknown => PresenceType.offline,
      UserPresenceStatus.online => PresenceType.online,
      UserPresenceStatus.unavailable => PresenceType.unavailable,
    };

    if (currentPresenceType != null &&
        matrixPresenceUpdateMatchesCurrent(
          currentPresence: currentPresenceType,
          currentStatusMessage: currentStatusMessage,
          nextPresence: matrixStatus,
          nextStatusMessage: statusMsg,
        )) {
      try {
        await _rememberPresence(
          self,
          matrixStatus,
          statusMsg: statusMsg,
          lastActiveAgo: currentLastActiveAgo,
          currentlyActive:
              currentCurrentlyActive ??
              (matrixStatus == PresenceType.online ? true : null),
        );
        Log.d(
          'Matrix presence local cache refreshed from matching server state '
          'user=${_matrixPresenceHash(self)} '
          'presence=${matrixStatus.name} '
          'status_msg=${_matrixPresenceStatusMsgMode(statusMsg, clearMessage)}'
          '${statusMsg == null ? '' : ' status_msg_length=${statusMsg.length}'}',
          category: LogCategory.matrix,
          source: 'presence',
        );
        _presenceRetryAfter = null;
        _loggedPresenceRateLimitSkip = false;
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content:
              'Failed to refresh Matrix presence cache from matching server state',
          category: LogCategory.matrix,
          source: 'presence',
        );
        rethrow;
      }
      return;
    }

    try {
      await _runPresenceNetworkOperation(
        () => _setPresence(self, matrixStatus, statusMsg: statusMsg),
      );
      await _rememberPresence(
        self,
        matrixStatus,
        statusMsg: statusMsg,
        currentlyActive: matrixStatus == PresenceType.online ? true : null,
      );
      Log.d(
        'Matrix presence local cache updated '
        'user=${_matrixPresenceHash(self)} '
        'presence=${matrixStatus.name} '
        'status_msg=${_matrixPresenceStatusMsgMode(statusMsg, clearMessage)}'
        '${statusMsg == null ? '' : ' status_msg_length=${statusMsg.length}'}',
        category: LogCategory.matrix,
        source: 'presence',
      );
      _presenceRetryAfter = null;
      _loggedPresenceRateLimitSkip = false;
    } catch (error, _) {
      final retryDelay = _rememberPresenceRetryDelay(error);
      _logPresenceUpdateFailure(
        error,
        userId: self,
        presence: matrixStatus,
        statusMsg: statusMsg,
        clearMessage: clearMessage,
      );
      if (retryDelay != null) {
        throw UserPresenceRateLimitException(retryAfter: retryDelay);
      }
      rethrow;
    }
  }

  Future<T> _runPresenceNetworkOperation<T>(Future<T> Function() operation) =>
      runZoned(
        operation,
        zoneValues: {
          Log.matrixNetworkOperationZoneKey: Log.matrixPresenceUpdateOperation,
        },
      );

  Future<void> _setPresence(
    String userId,
    PresenceType presence, {
    String? statusMsg,
  }) async {
    final matrixApi = client.matrixClient;
    final baseUri = matrixApi.baseUri;
    final bearerToken = matrixApi.bearerToken;
    if (baseUri == null || bearerToken == null || bearerToken.isEmpty) {
      throw StateError('Matrix presence update missing session state');
    }

    final requestUri = Uri(
      path: '_matrix/client/v3/presence/${Uri.encodeComponent(userId)}/status',
    );
    final response = await matrixApi.httpClient.put(
      baseUri.resolveUri(requestUri),
      headers: {
        'authorization': 'Bearer $bearerToken',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'presence': presence.name,
        if (statusMsg != null) 'status_msg': statusMsg,
      }),
    );

    if (response.statusCode != 200) {
      _throwPresenceResponse(response);
    }

    final responseText = utf8
        .decode(response.bodyBytes, allowMalformed: true)
        .trim();
    if (responseText.isEmpty) {
      return;
    }

    jsonDecode(responseText);
  }

  /// Test-only entry to [_rememberPresence].
  ///
  /// The database gate lives inside that method, and every public route to it
  /// goes through an HTTP PUT. A test that reached the gate through a mocked
  /// transport would be asserting the transport; this enters the unit that
  /// contains the gate, which is the thing that must not be removed.
  @visibleForTesting
  Future<CachedPresence> debugRememberPresenceForTesting(
    String userId,
    PresenceType presence, {
    String? statusMsg,
    int? lastActiveAgo,
    bool? currentlyActive,
  }) {
    return _rememberPresence(
      userId,
      presence,
      statusMsg: statusMsg,
      lastActiveAgo: lastActiveAgo,
      currentlyActive: currentlyActive,
    );
  }

  Future<CachedPresence> _rememberPresence(
    String userId,
    PresenceType presence, {
    String? statusMsg,
    int? lastActiveAgo,
    bool? currentlyActive,
  }) async {
    final cachedPresence = CachedPresence(
      presence,
      lastActiveAgo,
      matrixPresenceStatusMessageForCache(statusMsg),
      currentlyActive,
      userId,
    );

    if (_disposed) {
      return cachedPresence;
    }

    // Keep the Matrix SDK's fast presence reads aligned with direct PUTs.
    // ignore: deprecated_member_use
    client.matrixClient.presences[userId] = cachedPresence;

    // The WRITE half of the same gate the presence reads already use. This
    // path is lifecycle-driven: the inactivity timer fires on wake, or while
    // backgrounded-but-running, and reaches storePresence before the release
    // trigger has re-established the account database - where the connection
    // throws by design. Observed on device at 01:55:17Z after a suspend/resume
    // cycle, named end to end from setState -> setStatus -> here.
    //
    // TIMING: `waitForDatabase` waits while a database is merely released and
    // answers false only when a resume FAILS under it, re-arming for the next
    // one. So this awaits the store coming back rather than skipping straight
    // past, and only a failed resume takes the else branch.
    //
    // A failed gate skips only the PERSIST. The in-memory presence above and
    // the notification below still happen, because this row is a cache of a
    // value the server already has: dropping the cache write loses nothing a
    // later fetch cannot restore, while failing the whole call would discard
    // a presence change the user actually made.
    final databaseReady = await DatabaseReleaseTrigger.waitForDatabase(
      'presence.remember',
    );
    // Re-read the flag on the far side of the gate, the way `getUserPresence`
    // and `onLastSeenRemoved` already do on their reads. The gate SUSPENDS,
    // and a logout or account removal is exactly the kind of thing that
    // happens during that suspension - so waiting here and then writing means
    // writing to a database being torn down. `setStatus` awaits this call, so
    // that tear-down error would reach the user as a failed presence update.
    if (_disposed) {
      return cachedPresence;
    }
    if (databaseReady) {
      await client.matrixClient.database.storePresence(userId, cachedPresence);
    } else {
      // Said here rather than left to the gate's own line, because the caller
      // logs 'local cache updated' a few frames later and that stays true -
      // the memory copy above did happen. Only the persisted one did not.
      Log.w(
        'Matrix presence not persisted, database unavailable '
        'user=${_matrixPresenceHash(userId)} presence=${presence.name}',
        category: LogCategory.matrix,
        source: 'presence',
      );
    }
    if (!_disposed && !_controller.isClosed) {
      _controller.add((userId, convertPresence(cachedPresence)));
    }
    return cachedPresence;
  }

  Never _throwPresenceResponse(http.Response response) {
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final exception = MatrixException.fromJson(
          decoded.cast<String, Object?>(),
        );
        exception.response = response;
        throw exception;
      }
    } on MatrixException {
      rethrow;
    } catch (_) {
      // Fall through to a compact response exception below.
    }

    throw MatrixPresenceUpdateException(
      statusCode: response.statusCode,
      responseBody: body,
    );
  }

  Duration? _rememberPresenceRetryDelay(Object error) {
    final retryDelay = matrixPresenceRetryDelay(error);
    if (retryDelay == null) {
      return null;
    }

    final paddedDelay = retryDelay + _presenceRateLimitPadding;
    final nextAllowed = DateTime.now().add(paddedDelay);
    final current = _presenceRetryAfter;
    if (current == null || nextAllowed.isAfter(current)) {
      _presenceRetryAfter = nextAllowed;
    }

    _loggedPresenceRateLimitSkip = false;
    return paddedDelay;
  }

  Duration? _remainingPresenceRetryDelay() {
    final retryAfter = _presenceRetryAfter;
    if (retryAfter == null) {
      return null;
    }

    final remaining = retryAfter.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _presenceRetryAfter = null;
      _loggedPresenceRateLimitSkip = false;
      return null;
    }

    return remaining;
  }

  void _logPresenceUpdateFailure(
    Object error, {
    required String userId,
    required PresenceType presence,
    required String? statusMsg,
    required bool clearMessage,
  }) {
    final details = matrixPresenceFailureSummary(
      error,
      userId: userId,
      presence: presence,
      statusMsg: statusMsg,
      clearMessage: clearMessage,
    );
    final now = DateTime.now();
    final signature = matrixPresenceFailureSignature(error, presence);
    if (_lastPresenceFailureKey == signature &&
        _lastPresenceFailureLogAt != null &&
        now.difference(_lastPresenceFailureLogAt!) < Duration(seconds: 30)) {
      return;
    }

    _lastPresenceFailureKey = signature;
    _lastPresenceFailureLogAt = now;
    Log.w(
      'Matrix presence update rejected $details',
      category: LogCategory.matrix,
      source: 'presence',
    );
  }

  void onSync(SyncUpdate event) {
    if (_disposed) {
      return;
    }

    if (event.rooms?.join != null) {
      for (var update in event.rooms!.join!.entries) {
        handleEvents(update.value.ephemeral);
        handleEvents(update.value.state);
        handleTimelineUpdate(update.value.timeline);
      }
    }
  }

  void handleEvents(List<BasicEvent>? events) {
    if (_disposed) {
      return;
    }

    if (events == null) return;
    var time = DateTime.now();

    for (var event in events) {
      try {
        if (event.type == "m.typing") {
          handleTyping(event, time);
          continue;
        }

        if (event.type == "m.receipt") {
          handleReadReceipt(event);
          continue;
        }

        if (event.type == "m.room.member") {
          handleRoomMemberEvent(event);
          continue;
        }
      } catch (error, _) {
        Log.w(
          'Failed to handle Matrix presence event type=${event.type}: $error',
          category: LogCategory.matrix,
          source: 'presence',
        );
        continue;
      }
    }
  }

  void handleTyping(BasicEvent event, DateTime time) {
    for (var id in event.content["user_ids"] as List<dynamic>) {
      sawUser(id, time);
    }
  }

  void handleReadReceipt(BasicEvent event) {
    for (var event in event.content.values) {
      var read = (event as Map<String, dynamic>)["m.read"];
      if (read == null) continue;

      for (var entry in (read as Map<String, dynamic>).entries) {
        var value = entry.value as Map<String, dynamic>;

        if (value.containsKey("ts")) {
          sawUser(
            entry.key,
            DateTime.fromMicrosecondsSinceEpoch((value["ts"] as int) * 1000),
          );
        }
      }
    }
  }

  void handleTimelineUpdate(TimelineUpdate? timeline) async {
    if (_disposed) {
      return;
    }

    if (timeline?.events == null) return;

    for (var event in timeline!.events!) {
      sawUser(event.senderId, event.originServerTs);
    }
  }

  void sawUser(String id, DateTime timestamp) async {
    if (_disposed) {
      return;
    }

    final presence = await client.matrixClient.fetchCurrentPresence(
      id,
      fetchOnlyFromCached: true,
    );
    if (_disposed) {
      return;
    }

    final statusMessage = presence.statusMsg?.trim();
    if (presence.presence != PresenceType.offline ||
        (statusMessage != null && statusMessage.isNotEmpty)) {
      return;
    }

    if (DateTime.now().difference(timestamp).inSeconds < 60) {
      var seen = lastSeen.get(id);

      if (seen == null) {
        lastSeen.put(id, timestamp);
      } else {
        if (timestamp.isAfter(seen)) {
          lastSeen.put(id, timestamp);
        }
      }

      if (!_disposed && !_controller.isClosed) {
        _controller.add((id, UserPresence(UserPresenceStatus.online)));
      }
    }
  }

  void onLastSeenRemoved(String event) async {
    if (_disposed) {
      return;
    }

    // Timer-driven: the last-seen cache's cleaner fires on its own poll,
    // including while the app is backgrounded-and-running or in the first
    // seconds of a wake, and this read reached the released account
    // database as an unhandled zone error two seconds before the trigger's
    // `event=resumed` (iPhone, 2026-09-04). A timer that READS is bound by
    // the same rule as one that writes; waiting on the gate defers a
    // presence refresh, which costs nothing, and a failed gate is logged
    // where it happened.
    if (!await DatabaseReleaseTrigger.waitForDatabase('presence.last_seen') ||
        _disposed) {
      return;
    }

    final presence = await client.matrixClient.fetchCurrentPresence(
      event,
      fetchOnlyFromCached: true,
    );
    if (!_disposed &&
        !_controller.isClosed &&
        presence.presence == PresenceType.offline) {
      _controller.add((event, UserPresence(UserPresenceStatus.offline)));
    }
  }

  void handleRoomMemberEvent(BasicEvent event) {}

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    _subscriptions.clear();
    await lastSeen.dispose();
    _lastServerPresenceRefresh.clear();
    _serverPresenceRefreshes.clear();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

String? matrixPresenceStatusMessageForUpdate(
  String? currentStatusMessage, {
  String? message,
  bool clearMessage = false,
}) {
  if (clearMessage) {
    return '';
  }

  return message ?? currentStatusMessage;
}

String? matrixPresenceUserIdForUpdate({
  required String? matrixUserId,
  required String? profileUserId,
}) {
  if (matrixUserId != null && matrixUserId.isNotEmpty) {
    return matrixUserId;
  }

  if (profileUserId != null && profileUserId.isNotEmpty) {
    return profileUserId;
  }

  return null;
}

bool matrixPresenceUpdateMatchesCurrent({
  required PresenceType currentPresence,
  required String? currentStatusMessage,
  required PresenceType nextPresence,
  required String? nextStatusMessage,
}) {
  return currentPresence == nextPresence &&
      (currentStatusMessage ?? '') == (nextStatusMessage ?? '');
}

String? matrixPresenceStatusMessageForCache(String? statusMsg) {
  final trimmed = statusMsg?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  return statusMsg;
}

const matrixPresenceServerRefreshInterval = Duration(seconds: 45);

bool matrixPresenceShouldRefreshCachedPresence({
  required String? statusMsg,
  required DateTime? lastRefresh,
  required DateTime now,
  Duration refreshInterval = matrixPresenceServerRefreshInterval,
}) {
  final statusText = statusMsg?.trim();
  if (statusText != null && statusText.isNotEmpty) {
    return false;
  }

  if (lastRefresh == null) {
    return true;
  }

  return now.difference(lastRefresh) >= refreshInterval;
}

String matrixPresenceFailureSummary(
  Object error, {
  required String userId,
  required PresenceType presence,
  required String? statusMsg,
  required bool clearMessage,
}) {
  final fields = <String>[
    'user=${_matrixPresenceHash(userId)}',
    'presence=${presence.name}',
    'status_msg=${_matrixPresenceStatusMsgMode(statusMsg, clearMessage)}',
  ];

  if (statusMsg != null) {
    fields.add('status_msg_length=${statusMsg.length}');
  }

  fields.add('error_type=${_matrixPresenceErrorType(error)}');
  if (error is MatrixException) {
    fields.add('errcode=${Log.redactSensitiveInfo(error.errcode)}');
    fields.add('http_status=${error.response?.statusCode ?? 'unknown'}');
    final retryAfterMs = error.retryAfterMs;
    if (retryAfterMs != null) {
      fields.add('retry_after_ms=$retryAfterMs');
    }
    fields.add('message=${_matrixPresenceCompact(error.errorMessage)}');
  } else if (error is MatrixPresenceUpdateException) {
    fields.add('http_status=${error.statusCode}');
    fields.add('message=${_matrixPresenceCompact(error.responseBody)}');
  } else {
    fields.add('message=${_matrixPresenceCompact(error.toString())}');
  }

  return fields.join(' ');
}

String matrixPresenceFailureSignature(Object error, PresenceType presence) {
  if (error is MatrixException) {
    return [
      presence.name,
      error.errcode,
      error.response?.statusCode ?? 'unknown',
    ].join(':');
  }

  if (error is MatrixPresenceUpdateException) {
    return [presence.name, error.statusCode].join(':');
  }

  return [presence.name, _matrixPresenceErrorType(error)].join(':');
}

Duration? matrixPresenceRetryDelay(Object error) {
  if (error is UserPresenceRateLimitException) {
    return error.retryAfter;
  }

  if (error is MatrixException) {
    final retryAfterMs = error.retryAfterMs;
    if (retryAfterMs != null && retryAfterMs > 0) {
      return Duration(milliseconds: retryAfterMs);
    }

    if (error.response?.statusCode == 429) {
      return const Duration(seconds: 30);
    }
  }

  if (error is MatrixPresenceUpdateException && error.statusCode == 429) {
    return const Duration(seconds: 30);
  }

  return null;
}

class MatrixPresenceUpdateException implements Exception {
  const MatrixPresenceUpdateException({
    required this.statusCode,
    required this.responseBody,
  });

  final int statusCode;
  final String responseBody;

  @override
  String toString() {
    return 'Matrix presence update failed with HTTP $statusCode';
  }
}

String _matrixPresenceStatusMsgMode(String? statusMsg, bool clearMessage) {
  if (clearMessage || statusMsg == '') {
    return 'clear';
  }

  if (statusMsg == null) {
    return 'preserve';
  }

  return 'present';
}

String _matrixPresenceHash(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return 'none';
  }
  return sha256.convert(utf8.encode(text)).toString().substring(0, 12);
}

String _matrixPresenceErrorType(Object error) {
  final text = error.runtimeType.toString();
  return text.isEmpty ? 'unknown' : text;
}

String _matrixPresenceCompact(String? value, {int max = 120}) {
  if (value == null || value.isEmpty) {
    return 'none';
  }

  final cleaned = Log.redactSensitiveInfo(
    value,
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) {
    return 'none';
  }

  if (cleaned.length <= max) {
    return cleaned;
  }

  return '${cleaned.substring(0, max)}...';
}
