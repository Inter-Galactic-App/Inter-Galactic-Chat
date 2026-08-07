import 'dart:async';
import 'dart:convert';

import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_publisher.dart';
import 'package:intergalactic/client/components/activity/activity_settings.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/client/matrix/components/user_presence/matrix_user_presence.dart'
    show matrixPresenceRetryDelay;
import 'package:intergalactic/debug/log.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ActivityPresenceTargetProvider = List<ActivityPresenceTarget>
    Function();

class ActivityPresenceTarget {
  const ActivityPresenceTarget({
    required this.id,
    required this.presence,
    this.selfUserId,
  });

  final String id;
  final UserPresenceComponent presence;
  final String? selfUserId;
}

abstract class ActivityPresenceOwnershipStore {
  Future<String?> readSummary(String targetId);
  Future<void> writeSummary(String targetId, String summary);
  Future<void> clearSummary(String targetId);
}

class SharedPreferencesActivityPresenceOwnershipStore
    implements ActivityPresenceOwnershipStore {
  static const _storageKey = 'matrix_activity_presence_last_published';

  Future<Map<String, String>> _readAll() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return <String, String>{};
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <String, String>{};
    }

    return decoded.map<String, String>(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  Future<void> _writeAll(Map<String, String> values) async {
    final preferences = await SharedPreferences.getInstance();
    if (values.isEmpty) {
      await preferences.remove(_storageKey);
      return;
    }

    await preferences.setString(_storageKey, jsonEncode(values));
  }

  @override
  Future<String?> readSummary(String targetId) async {
    return (await _readAll())[targetId];
  }

  @override
  Future<void> writeSummary(String targetId, String summary) async {
    final values = await _readAll();
    values[targetId] = summary;
    await _writeAll(values);
  }

  @override
  Future<void> clearSummary(String targetId) async {
    final values = await _readAll();
    values.remove(targetId);
    await _writeAll(values);
  }
}

class MatrixActivityPresencePublisher implements ActivityPublisher {
  MatrixActivityPresencePublisher({
    required ActivityPresenceTargetProvider targetProvider,
    ActivityPresenceSummaryFormatter formatter =
        const ActivityPresenceSummaryFormatter(),
    ActivityPresenceOwnershipStore? ownershipStore,
    List<Duration> retryDelays = const [
      Duration(seconds: 5),
      Duration(seconds: 30),
      Duration(minutes: 2),
    ],
    Duration serverRetryPadding = const Duration(milliseconds: 750),
  })  : _targetProvider = targetProvider,
        _formatter = formatter,
        _ownershipStore =
            ownershipStore ?? SharedPreferencesActivityPresenceOwnershipStore(),
        _retryDelays = retryDelays,
        _serverRetryPadding = serverRetryPadding;

  factory MatrixActivityPresencePublisher.forClientManager(
    ClientManager? Function() clientManagerProvider,
  ) {
    return MatrixActivityPresencePublisher(
      targetProvider: () {
        final manager = clientManagerProvider();
        if (manager == null) {
          return const [];
        }

        return manager.clients
            .where((client) => client.isLoggedIn())
            .map((client) {
              final presence = client.getComponent<UserPresenceComponent>();
              if (presence == null) {
                return null;
              }

              return ActivityPresenceTarget(
                id: client.identifier,
                presence: presence,
                selfUserId: client.self?.identifier,
              );
            })
            .whereType<ActivityPresenceTarget>()
            .toList(growable: false);
      },
    );
  }

  final ActivityPresenceTargetProvider _targetProvider;
  final ActivityPresenceSummaryFormatter _formatter;
  final ActivityPresenceOwnershipStore _ownershipStore;
  final List<Duration> _retryDelays;
  final Duration _serverRetryPadding;
  final Map<String, _PublishedPresence> _lastPublished = {};
  final Map<String, ActivityPresenceTarget> _ownedTargets = {};
  Future<void> _publishChain = Future<void>.value();
  Timer? _retryTimer;
  DateTime? _serverRetryAfter;
  Duration? _serverSuggestedRetryDelay;
  UserActivity? _lastRequestedActivity;
  ActivitySettings? _lastRequestedSettings;
  UserActivity? _targetWaitActivity;
  ActivitySettings? _targetWaitSettings;
  int _retryAttempt = 0;
  bool _waitingForTargets = false;
  bool _loggedPersistentTargetRetry = false;
  bool _loggedServerRetryDelay = false;

  @override
  String get id => 'matrix_presence';

  @override
  Future<void> publish(
    UserActivity? activity,
    ActivitySettings settings,
  ) {
    _lastRequestedActivity = activity;
    _lastRequestedSettings = settings;
    final serverRetryDelay = _remainingServerRetryDelay();
    if (serverRetryDelay != null) {
      _waitingForTargets = false;
      _scheduleRetry(minimumDelay: serverRetryDelay);
      return _publishChain;
    }

    _cancelRetry();
    _retryAttempt = 0;
    _waitingForTargets = false;
    _loggedPersistentTargetRetry = false;
    _loggedServerRetryDelay = false;

    _publishChain = _publishChain
        .catchError((_) {})
        .then((_) => _publishAndMaybeRetry(activity, settings));
    return _publishChain;
  }

  Future<void> _publishAndMaybeRetry(
    UserActivity? activity,
    ActivitySettings settings,
  ) async {
    final success = await _publishInternal(activity, settings);
    if (success) {
      _retryAttempt = 0;
      _serverRetryAfter = null;
      _serverSuggestedRetryDelay = null;
      _loggedServerRetryDelay = false;
      return;
    }

    _scheduleRetry(minimumDelay: _serverSuggestedRetryDelay);
  }

  Future<bool> _publishInternal(
    UserActivity? activity,
    ActivitySettings settings,
  ) async {
    _serverSuggestedRetryDelay = null;
    var success = true;
    var summary = _formatter.format(activity, settings);
    final targets = _targetProvider();
    _waitingForTargets = targets.isEmpty;
    if (summary != null && targets.isEmpty) {
      _rememberTargetWait(activity, settings);
      Log.d(
        'Matrix activity presence publish waiting for logged-in targets',
        category: LogCategory.matrix,
        source: 'activity-presence',
      );
      return false;
    }

    if (activity == null) {
      _clearTargetWait();
    }

    final pendingActivity = _targetWaitActivity;
    final pendingSettings = _targetWaitSettings;
    if (summary == null && pendingActivity != null && pendingSettings != null) {
      final originalPendingSummary =
          _formatter.format(pendingActivity, pendingSettings);
      final pendingSummary = _formatter.format(pendingActivity, settings);
      if (originalPendingSummary == null || pendingSummary == null) {
        _clearTargetWait();
      } else {
        summary = pendingSummary;
        _rememberTargetWait(pendingActivity, settings);
        if (targets.isEmpty) {
          Log.d(
            'Matrix activity presence publish waiting for logged-in targets',
            category: LogCategory.matrix,
            source: 'activity-presence',
          );
          return false;
        }
      }
    }

    if (summary == null && targets.isEmpty && _ownedTargets.isEmpty) {
      Log.d(
        'Matrix activity presence clear waiting for logged-in targets',
        category: LogCategory.matrix,
        source: 'activity-presence',
      );
      return false;
    }

    if (targets.isNotEmpty) {
      _clearTargetWait();
    }

    final activeTargetIds = targets.map((target) => target.id).toSet();
    var appliedTargets = 0;
    for (final entry in _ownedTargets.entries
        .where((entry) => !activeTargetIds.contains(entry.key))
        .toList(growable: false)) {
      success = await _clearIfOwned(entry.value) && success;
      if (_serverSuggestedRetryDelay != null) {
        break;
      }
    }
    if (_serverSuggestedRetryDelay != null) {
      return false;
    }

    for (final target in targets) {
      if (summary == null) {
        success = await _clearIfOwned(target) && success;
        if (_serverSuggestedRetryDelay != null) {
          break;
        }
        continue;
      }

      try {
        final status = await _publishStatus(target);
        if (status == null) {
          success = false;
          continue;
        }

        final nextPublished = _PublishedPresence(
          summary: summary,
          status: status,
        );
        if (_lastPublished[target.id] == nextPublished) {
          _ownedTargets[target.id] = target;
          continue;
        }

        await target.presence.setStatus(status, message: summary);
        appliedTargets++;
        _lastPublished[target.id] = nextPublished;
        _ownedTargets[target.id] = target;
        await _rememberPublishedSummary(target.id, summary);
      } catch (error, stackTrace) {
        final serverRetry = _rememberServerRetryDelay(error);
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to publish Matrix activity presence',
          category: LogCategory.matrix,
          source: 'activity-presence',
        );
        success = false;
        if (serverRetry) {
          break;
        }
      }
    }

    if (summary != null && appliedTargets > 0) {
      Log.d(
        'Matrix activity presence publish applied '
        'targets=$appliedTargets status_msg_length=${summary.length}',
        category: LogCategory.matrix,
        source: 'activity-presence',
      );
    }

    return success;
  }

  void _rememberTargetWait(
    UserActivity? activity,
    ActivitySettings settings,
  ) {
    if (activity == null) {
      return;
    }

    _targetWaitActivity = activity;
    _targetWaitSettings = settings;
    _lastRequestedActivity = activity;
    _lastRequestedSettings = settings;
  }

  void _clearTargetWait() {
    _targetWaitActivity = null;
    _targetWaitSettings = null;
  }

  Future<bool> _clearIfOwned(ActivityPresenceTarget target) async {
    try {
      final presence = await _readCurrentPresence(target);
      final expectedSummary = _lastPublished[target.id]?.summary ??
          await _lastPublishedSummary(target.id);
      if (expectedSummary == null) {
        _lastPublished.remove(target.id);
        _ownedTargets.remove(target.id);
        await _forgetPublishedSummary(target.id);
        return true;
      }

      if (presence == null) {
        return false;
      }

      final currentSummary = presence.message?.message;
      if (target.selfUserId != null && currentSummary != expectedSummary) {
        _lastPublished.remove(target.id);
        _ownedTargets.remove(target.id);
        await _forgetPublishedSummary(target.id);
        return true;
      }

      final status = presence.status;
      await target.presence.setStatus(status, clearMessage: true);
      _lastPublished.remove(target.id);
      _ownedTargets.remove(target.id);
      await _forgetPublishedSummary(target.id);
      return true;
    } catch (error, stackTrace) {
      _rememberServerRetryDelay(error);
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to clear Matrix activity presence',
        category: LogCategory.matrix,
        source: 'activity-presence',
      );
      return false;
    }
  }

  bool _rememberServerRetryDelay(Object error) {
    final retryDelay = matrixPresenceRetryDelay(error);
    if (retryDelay == null) {
      return false;
    }

    final paddedDelay = retryDelay + _serverRetryPadding;
    final nextAllowed = DateTime.now().add(paddedDelay);
    final current = _serverRetryAfter;
    if (current == null || nextAllowed.isAfter(current)) {
      _serverRetryAfter = nextAllowed;
    }

    final suggested = _serverSuggestedRetryDelay;
    if (suggested == null || paddedDelay > suggested) {
      _serverSuggestedRetryDelay = paddedDelay;
    }

    return true;
  }

  Duration? _remainingServerRetryDelay() {
    final retryAfter = _serverRetryAfter;
    if (retryAfter == null) {
      return null;
    }

    final remaining = retryAfter.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _serverRetryAfter = null;
      _loggedServerRetryDelay = false;
      return null;
    }

    return remaining;
  }

  Future<String?> _lastPublishedSummary(String targetId) async {
    try {
      return await _ownershipStore.readSummary(targetId);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to read Matrix activity presence ownership marker',
        category: LogCategory.matrix,
        source: 'activity-presence',
      );
      return null;
    }
  }

  Future<void> _rememberPublishedSummary(
    String targetId,
    String summary,
  ) async {
    try {
      await _ownershipStore.writeSummary(targetId, summary);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to store Matrix activity presence ownership marker',
        category: LogCategory.matrix,
        source: 'activity-presence',
      );
    }
  }

  Future<void> _forgetPublishedSummary(String targetId) async {
    try {
      await _ownershipStore.clearSummary(targetId);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to clear Matrix activity presence ownership marker',
        category: LogCategory.matrix,
        source: 'activity-presence',
      );
    }
  }

  Future<UserPresenceStatus?> _publishStatus(
    ActivityPresenceTarget target,
  ) async {
    final current = await _readCurrentPresence(target);
    if (current == null) {
      return null;
    }

    return switch (current.status) {
      UserPresenceStatus.unavailable => UserPresenceStatus.unavailable,
      _ => UserPresenceStatus.online,
    };
  }

  Future<UserPresence?> _readCurrentPresence(
      ActivityPresenceTarget target) async {
    final selfUserId = target.selfUserId;
    if (selfUserId == null || selfUserId.isEmpty) {
      return UserPresence(UserPresenceStatus.online);
    }

    try {
      return await target.presence.getUserPresence(selfUserId);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to read Matrix presence before activity update',
        category: LogCategory.matrix,
        source: 'activity-presence',
      );
      return null;
    }
  }

  void _scheduleRetry({Duration? minimumDelay}) {
    if (_retryTimer != null) {
      return;
    }

    if (_retryDelays.isEmpty && minimumDelay == null) {
      return;
    }

    final retryBudgetAvailable = _retryAttempt < _retryDelays.length;
    final keepWaitingForTargets =
        _waitingForTargets && _lastRequestedSettings != null;
    final keepWaitingForServer = minimumDelay != null;

    if (!retryBudgetAvailable &&
        !keepWaitingForTargets &&
        !keepWaitingForServer) {
      Log.w(
        'Giving up retrying Matrix activity presence after '
        '${_retryDelays.length} attempts',
        category: LogCategory.matrix,
        source: 'activity-presence',
      );
      return;
    }

    if (!retryBudgetAvailable &&
        keepWaitingForTargets &&
        !_loggedPersistentTargetRetry) {
      Log.d(
        'Continuing Matrix activity presence retries until logged-in targets are available',
        category: LogCategory.matrix,
        source: 'activity-presence',
      );
      _loggedPersistentTargetRetry = true;
    }

    final backoffDelay = retryBudgetAvailable
        ? _retryDelays[_retryAttempt++]
        : (_retryDelays.isEmpty ? Duration.zero : _retryDelays.last);
    final delay = minimumDelay != null && minimumDelay > backoffDelay
        ? minimumDelay
        : backoffDelay;
    if (minimumDelay != null && !_loggedServerRetryDelay) {
      Log.d(
        'Deferring Matrix activity presence until server rate limit resets',
        category: LogCategory.matrix,
        source: 'activity-presence',
      );
      _loggedServerRetryDelay = true;
    }

    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      final settings = _lastRequestedSettings;
      if (settings == null) {
        return;
      }

      _publishChain =
          _publishChain.catchError((_) {}).then((_) => _publishAndMaybeRetry(
                _lastRequestedActivity,
                settings,
              ));
      unawaited(_publishChain);
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}

class _PublishedPresence {
  const _PublishedPresence({
    required this.summary,
    required this.status,
  });

  final String summary;
  final UserPresenceStatus status;

  @override
  bool operator ==(Object other) {
    return other is _PublishedPresence &&
        other.summary == summary &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(summary, status);
}
