import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('notification preview privacy preferences', () {
    test(
      'new installs default to private and remain ready for first-use setup',
      () async {
        SharedPreferences.setMockInitialValues({});

        final preferences = Preferences();
        await preferences.init();

        expect(preferences.shouldShowNotificationPreviewPrivacyChoice, isTrue);
        expect(preferences.usePrivateNotificationPreviews, isTrue);
        expect(
          preferences.notificationPreviewPrivacyChoiceValue.value,
          Preferences.notificationPreviewPrivacyChoicePrivate,
        );
      },
    );

    test(
      'existing account state preserves rich defaults without prompting',
      () async {
        SharedPreferences.setMockInitialValues({
          Preferences.registeredMatrixClients: <String>['client-a'],
        });

        final preferences = Preferences();
        await preferences.init();

        expect(preferences.shouldShowNotificationPreviewPrivacyChoice, isFalse);
        expect(preferences.usePrivateNotificationPreviews, isFalse);
        expect(
          preferences.notificationPreviewPrivacyChoiceValue.value,
          Preferences.notificationPreviewPrivacyChoiceRich,
        );
        expect(preferences.formatNotificationBody.value, isTrue);
        expect(preferences.showMediaInNotifications.value, isTrue);
        expect(preferences.previewUrlInNotifications.value, isTrue);
        expect(preferences.notificationCompanionShowPreviews.value, isTrue);
      },
    );

    test('existing preview preference state is preserved as custom', () async {
      SharedPreferences.setMockInitialValues({
        'format_notification_body': false,
      });

      final preferences = Preferences();
      await preferences.init();

      expect(preferences.shouldShowNotificationPreviewPrivacyChoice, isFalse);
      expect(preferences.usePrivateNotificationPreviews, isFalse);
      expect(
        preferences.notificationPreviewPrivacyChoiceValue.value,
        Preferences.notificationPreviewPrivacyChoiceCustom,
      );
      expect(preferences.formatNotificationBody.value, isFalse);
    });

    test('private choice disables readable preview helpers', () async {
      SharedPreferences.setMockInitialValues({});

      final preferences = Preferences();
      await preferences.init();
      await preferences.applyNotificationPreviewPrivacyChoice(
        Preferences.notificationPreviewPrivacyChoicePrivate,
      );

      expect(preferences.shouldShowNotificationPreviewPrivacyChoice, isFalse);
      expect(preferences.usePrivateNotificationPreviews, isTrue);
      expect(preferences.formatNotificationBody.value, isFalse);
      expect(preferences.showMediaInNotifications.value, isFalse);
      expect(preferences.previewUrlInNotifications.value, isFalse);
      expect(preferences.notificationCompanionShowPreviews.value, isFalse);
    });

    test('rich choice enables readable preview helpers', () async {
      SharedPreferences.setMockInitialValues({
        'format_notification_body': false,
        'show_media_in_notifications': false,
        'preview_urls_in_notification': false,
        'notification_companion_show_previews': false,
      });

      final preferences = Preferences();
      await preferences.init();
      await preferences.applyNotificationPreviewPrivacyChoice(
        Preferences.notificationPreviewPrivacyChoiceRich,
      );

      expect(preferences.shouldShowNotificationPreviewPrivacyChoice, isFalse);
      expect(preferences.usePrivateNotificationPreviews, isFalse);
      expect(preferences.formatNotificationBody.value, isTrue);
      expect(preferences.showMediaInNotifications.value, isTrue);
      expect(preferences.previewUrlInNotifications.value, isTrue);
      expect(preferences.notificationCompanionShowPreviews.value, isTrue);
    });
  });
}
