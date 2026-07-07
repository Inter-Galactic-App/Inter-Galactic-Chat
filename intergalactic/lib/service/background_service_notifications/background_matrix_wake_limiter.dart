import 'package:shared_preferences/shared_preferences.dart';

class BackgroundMatrixWakeLimiter {
  static const defaultMinInterval = Duration(seconds: 12);
  static const _lastStartedPrefix =
      'background_matrix_wake_sync_last_started_ms.';

  static final Set<String> _claimsInProgress = {};
  static final Map<String, DateTime> _lastStartedInMemory = {};

  static Future<bool> claim(
    String clientId, {
    Duration minInterval = defaultMinInterval,
    DateTime? now,
  }) async {
    if (_claimsInProgress.contains(clientId)) {
      return false;
    }

    final claimedAt = now ?? DateTime.now();
    final lastInMemory = _lastStartedInMemory[clientId];
    if (_isInsideInterval(lastInMemory, claimedAt, minInterval)) {
      return false;
    }

    _claimsInProgress.add(clientId);
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = keyForClient(clientId);
      final lastStartedMs = preferences.getInt(key);
      final lastStarted = lastStartedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastStartedMs);

      if (_isInsideInterval(lastStarted, claimedAt, minInterval)) {
        _lastStartedInMemory[clientId] = lastStarted!;
        return false;
      }

      await preferences.setInt(key, claimedAt.millisecondsSinceEpoch);
      _lastStartedInMemory[clientId] = claimedAt;
      return true;
    } finally {
      _claimsInProgress.remove(clientId);
    }
  }

  static String keyForClient(String clientId) {
    return '$_lastStartedPrefix${Uri.encodeComponent(clientId)}';
  }

  static bool _isInsideInterval(
    DateTime? lastStarted,
    DateTime now,
    Duration minInterval,
  ) {
    return lastStarted != null && now.difference(lastStarted) < minInterval;
  }

  static void resetForTests() {
    _claimsInProgress.clear();
    _lastStartedInMemory.clear();
  }
}
