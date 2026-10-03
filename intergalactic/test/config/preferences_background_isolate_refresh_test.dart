// Android renders message notifications in a background isolate, and each
// isolate gets its own SharedPreferences cache built once when it starts. A
// setting changed in the UI isolate lands on disk but never invalidates that
// cache, so the background isolate keeps rendering against the startup value.
// The isolate survives backgrounding and dies only on a full app close, which
// is exactly the reported symptom: "changing the setting does not apply until
// the app has been fully closed and reopened".
//
// The store here stands in for the other isolate: writing to it directly is
// what a write from a DIFFERENT isolate looks like from this one - it reaches
// the platform without touching this isolate's cache.

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Preferences preferences;

  setUp(() async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'show_media_in_notifications': true,
    });
    preferences = Preferences();
    await preferences.init();
  });

  /// Writes as another isolate would: straight to the backing store, leaving
  /// this isolate's `SharedPreferences` instance and its cache untouched.
  ///
  /// `setMockInitialValues` cannot stand in for this. It also nulls the
  /// memoised instance, so the next `getInstance()` returns a FRESH cache -
  /// which made an earlier version of the repeat-init test below pass with the
  /// reload deleted.
  Future<void> writeFromAnotherIsolate(bool value) =>
      SharedPreferencesStorePlatform.instance.setValue(
        'Bool',
        'flutter.show_media_in_notifications',
        value,
      );

  test('a write from another isolate is invisible until a refresh', () async {
    expect(preferences.showMediaInNotifications.value, isTrue);

    await writeFromAnotherIsolate(false);
    expect(
      preferences.showMediaInNotifications.value,
      isTrue,
      reason:
          'this pins the defect rather than the fix: without a refresh the '
          'background isolate still reads its startup snapshot',
    );

    await preferences.refreshFromDisk();
    expect(
      preferences.showMediaInNotifications.value,
      isFalse,
      reason:
          'the setting the user changed must be the one a notification '
          'renders against, without waiting for a full app restart',
    );
  });

  test(
    'a repeat init refreshes, because that is all it can usefully do',
    () async {
      // The background message entry points call `preferences.init()` per
      // message. That looked like a refresh and was not: getInstance() returns
      // the memoised per-isolate cache, so the call re-ran the migrations and
      // changed nothing a reader would see.
      await writeFromAnotherIsolate(false);
      expect(preferences.showMediaInNotifications.value, isTrue);

      await preferences.init();

      expect(preferences.showMediaInNotifications.value, isFalse);
    },
  );

  test('init against a REPLACED store runs the migrations', () async {
    // The #305 regression. The refresh shortcut was taken on the strength of
    // `isInit` alone, so a second `init()` returned early no matter what it
    // had just been handed - and when the store underneath had been replaced,
    // its contents were never migrated. In the app that is a fresh cache; in
    // a test run it is the next test's `setMockInitialValues`, which is how
    // one file's fourth test began rendering redacted notifications for an
    // install the migration should have marked as rich-preview.
    //
    // Sequenced the way it happens: this file's setUp has already run one
    // `init()`, so `isInit` is true before the store is swapped, exactly as a
    // later test in a shared run finds it.
    SharedPreferences.setMockInitialValues(<String, Object>{
      Preferences.registeredMatrixClients: <String>['client-a'],
    });

    await preferences.init();

    expect(
      preferences.usePrivateNotificationPreviews,
      isFalse,
      reason:
          'an install with existing account state and no preview preferences '
          'is migrated to rich previews; skipping that leaves the private '
          'default in place and redacts notifications that should not be',
    );
    expect(preferences.notificationPreviewPrivacyChoiceCompleted.value, isTrue);
  });

  test('refreshing before init does nothing rather than throwing', () async {
    final fresh = Preferences();

    await expectLater(fresh.refreshFromDisk(), completes);
    expect(fresh.isInit, isFalse);
  });
}
