// A background notification isolate refreshes preferences before rendering
// each queued entry, because its own cache is a startup snapshot that never
// sees the UI isolate's writes. When that read FAILS the entry is still
// rendered - dropping it would lose the message, and the queue guard exists so
// one unreadable read does not discard the rest.
//
// What must not survive a failed read is the RICH preview. The cache may
// predate the user turning previews off, so rendering against it puts message
// content on a lock screen the user has just asked to keep clear. The read
// therefore fails CLOSED: an unrefreshable cache reports private previews.
//
// The store below fails only the read `refreshFromDisk` performs, so the
// failure under test is that read and not a broken preferences setup.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/hide_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesStorePlatform realStore;
  late _RefreshFailingStore failingStore;

  setUp(() async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await preferences.init();
    // Rich previews, chosen deliberately: the private default would make every
    // assertion below pass without the fix.
    await preferences.applyNotificationPreviewPrivacyChoice(
      Preferences.notificationPreviewPrivacyChoiceRich,
    );
    realStore = SharedPreferencesStorePlatform.instance;
    failingStore = _RefreshFailingStore(realStore);
  });

  tearDown(() async {
    SharedPreferencesStorePlatform.instance = realStore;
  });

  MessageNotificationContent buildMessage() => MessageNotificationContent(
    senderName: 'Nova',
    senderId: '@nova:test',
    roomName: 'Bridge',
    content: 'Launch codes',
    eventId: r'$event',
    roomId: '!room:test',
    clientId: 'client-a',
    isDirectMessage: false,
  );

  test('a failed refresh makes the preview read fail closed', () async {
    expect(
      preferences.usePrivateNotificationPreviews,
      isFalse,
      reason:
          'arms the check: with rich previews chosen and a readable cache the '
          'getter must say false, or the assertion below proves nothing',
    );

    SharedPreferencesStorePlatform.instance = failingStore;
    await expectLater(
      preferences.refreshFromDisk(),
      throwsA(isA<FileSystemException>()),
    );

    expect(
      failingStore.refreshAttempts,
      1,
      reason:
          'arms the check: the refresh has to have reached the throwing store',
    );
    expect(
      preferences.cacheRefreshFailed,
      isTrue,
      reason: 'the failure must be recorded, not only rethrown',
    );
    expect(
      preferences.usePrivateNotificationPreviews,
      isTrue,
      reason:
          'the cache may predate the user turning previews off, so an '
          'unrefreshable cache must be read as private',
    );
  });

  test('a stale cache redacts the notification it renders', () async {
    final control = buildMessage();
    await NotificationModifierHideContent().process(control);
    expect(
      control.content,
      'Launch codes',
      reason:
          'arms the check: with a readable rich-preview cache the modifier '
          'leaves the body alone',
    );

    SharedPreferencesStorePlatform.instance = failingStore;
    await expectLater(preferences.refreshFromDisk(), throwsA(anything));

    final content = buildMessage();
    await NotificationModifierHideContent().process(content);

    expect(
      content.title,
      NotificationModifierHideContent.genericNotificationTitle,
    );
    expect(content.roomName, NotificationModifierHideContent.genericRoomName);
    // Through the getter rather than a literal: the redacted body is localized
    // via Intl.message, so a hardcoded string would fail on a wording change
    // instead of on a behaviour change.
    expect(
      content.content,
      NotificationModifierHideContent().notificationModifiersPrivacyEnhanced,
    );
    expect(content.senderId, '@nova:test');
    expect(content.roomId, '!room:test');
    expect(content.eventId, r'$event');
    expect(
      content.clientId,
      'client-a',
      reason: 'routing metadata is not what the redaction is for',
    );
  });

  test('a later successful refresh clears the fail-closed state', () async {
    SharedPreferencesStorePlatform.instance = failingStore;
    await expectLater(preferences.refreshFromDisk(), throwsA(anything));
    expect(preferences.usePrivateNotificationPreviews, isTrue);

    // The background loop refreshes once per queued entry, so the very next
    // entry after a transient failure must render rich previews again - a
    // latch here would redact every notification until the app was restarted.
    SharedPreferencesStorePlatform.instance = realStore;
    await preferences.refreshFromDisk();

    expect(preferences.cacheRefreshFailed, isFalse);
    expect(preferences.usePrivateNotificationPreviews, isFalse);
  });
}

/// Fails the read behind `refreshFromDisk` and nothing else; writes still go to
/// the real mock store so the rest of the preferences setup is untouched.
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
