// The per-entry preference refresh sat outside every guard. handleMessage has
// its own try/catch, so a failure there costs one notification - but a failure
// in the refresh reached flushQueueLoop's OUTER catch, which abandons the loop,
// discards every notification still queued, and posts the generic fallback. A
// transient read is exactly what happens while the UI isolate writes
// preferences, and the v1 manager already runs the same call inside its
// per-entry try.
//
// The store below fails only the read `refreshFromDisk` performs, so the
// failure is the one under test and not a broken preferences setup.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/service/background_service_notifications/background_service_task_notification2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesStorePlatform realStore;
  late _RefreshFailingStore store;

  setUp(() async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await preferences.init();
    realStore = SharedPreferencesStorePlatform.instance;
    store = _RefreshFailingStore(realStore);
    SharedPreferencesStorePlatform.instance = store;
  });

  tearDown(() {
    SharedPreferencesStorePlatform.instance = realStore;
  });

  test('a failed refresh does not discard the rest of the queue', () async {
    final manager = _RecordingManager();
    manager.queue.addAll([
      <String, dynamic>{'room_id': '!a:example.org', 'event_id': r'$one'},
      <String, dynamic>{'room_id': '!b:example.org', 'event_id': r'$two'},
    ]);

    await manager.flushQueueLoop();

    expect(
      store.refreshAttempts,
      2,
      reason:
          'arms the check: if the refresh never reached the throwing store '
          'this test would pass against the unguarded call too',
    );
    expect(
      manager.handled.map((entry) => entry['event_id']),
      [r'$one', r'$two'],
      reason:
          'a failed read costs the refresh for that entry, not the queue - '
          'the second notification must still be rendered',
    );
  });
}

/// Records what the loop dispatched. [handleMessage] carries its own error
/// handling in production and stands up none of the notification stack here.
class _RecordingManager extends BackgroundNotificationsManager2 {
  _RecordingManager() : super(null, stopServiceWhenIdle: false);

  final List<Map<String, dynamic>> handled = [];

  @override
  Future<void> handleMessage(Map<String, dynamic> data) async {
    handled.add(data);
  }
}

/// Fails the read behind `refreshFromDisk` and nothing else; writes still go
/// to the real mock store so the rest of the preferences setup is untouched.
class _RefreshFailingStore extends SharedPreferencesStorePlatform {
  _RefreshFailingStore(this._inner);

  final SharedPreferencesStorePlatform _inner;

  int refreshAttempts = 0;

  @override
  Future<Map<String, Object>> getAll() async {
    refreshAttempts++;
    throw FileSystemException('preferences temporarily unreadable');
  }

  @override
  Future<bool> remove(String key) => _inner.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _inner.setValue(valueType, key, value);

  @override
  Future<bool> clear() => _inner.clear();
}
