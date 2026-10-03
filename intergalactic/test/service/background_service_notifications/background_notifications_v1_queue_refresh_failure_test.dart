// The v1 manager ran the per-entry preference refresh inside the SAME try as
// handleMessage, so a failed read skipped the notification entirely - the
// entry was already removed from the queue, and nothing rendered it. Stale
// preferences would have produced a correct-enough notification, and the
// privacy read fails closed on its own while the cache is unrefreshed, so
// losing the message was the worse outcome of the two.
//
// The v2 manager's comment claimed this file already guarded the refresh
// separately. It did not; this test is what makes that claim true.
//
// The store below fails only the read `refreshFromDisk` performs, so the
// failure is the one under test and not a broken preferences setup.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/service/background_service_notifications/background_service_task_notification.dart';
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

  test('a failed refresh still renders the entry it was for', () async {
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
          'a failed read costs the refresh for that entry, not the entry - '
          'the queue has already given up its only copy of the message',
    );
  });
}

/// Records what the loop dispatched. [handleMessage] stands up none of the
/// notification stack here; the loop's dispatch decision is what is under test.
class _RecordingManager extends BackgroundNotificationsManager {
  _RecordingManager() : super(null);

  final List<Map<String, dynamic>> handled = [];

  @override
  Future<void> handleMessage(Map<String, dynamic> data) async {
    handled.add(Map<String, dynamic>.of(data));
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
