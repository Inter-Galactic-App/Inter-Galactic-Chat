import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('encrypted URL preview preferences', () {
    test('new installs wait for first-use consent before fetching', () async {
      SharedPreferences.setMockInitialValues({});

      final preferences = Preferences();
      await preferences.init();

      expect(preferences.shouldShowUrlPreviewE2EEConsentChoice, isTrue);
      expect(preferences.urlPreviewInE2EEChat.value, isFalse);
      expect(preferences.shouldAllowUrlPreviewInE2EEChat, isFalse);
    });

    test(
      'existing account state keeps previous enabled-by-default behavior',
      () async {
        SharedPreferences.setMockInitialValues({
          Preferences.registeredMatrixClients: <String>['client-a'],
        });

        final preferences = Preferences();
        await preferences.init();

        expect(preferences.shouldShowUrlPreviewE2EEConsentChoice, isFalse);
        expect(preferences.urlPreviewInE2EEChat.value, isTrue);
        expect(preferences.shouldAllowUrlPreviewInE2EEChat, isTrue);
      },
    );

    test(
      'existing explicit encrypted preview preference is preserved',
      () async {
        SharedPreferences.setMockInitialValues({
          'use_url_preview_in_e2ee_chat': false,
        });

        final preferences = Preferences();
        await preferences.init();

        expect(preferences.shouldShowUrlPreviewE2EEConsentChoice, isFalse);
        expect(preferences.urlPreviewInE2EEChat.value, isFalse);
        expect(preferences.shouldAllowUrlPreviewInE2EEChat, isFalse);
      },
    );

    test('first-use choice records consent and updates fetch gate', () async {
      SharedPreferences.setMockInitialValues({});

      final preferences = Preferences();
      await preferences.init();
      await preferences.applyUrlPreviewE2EEConsentChoice(allow: true);

      expect(preferences.shouldShowUrlPreviewE2EEConsentChoice, isFalse);
      expect(preferences.urlPreviewInE2EEChat.value, isTrue);
      expect(preferences.shouldAllowUrlPreviewInE2EEChat, isTrue);

      await preferences.applyUrlPreviewE2EEConsentChoice(allow: false);

      expect(preferences.shouldShowUrlPreviewE2EEConsentChoice, isFalse);
      expect(preferences.urlPreviewInE2EEChat.value, isFalse);
      expect(preferences.shouldAllowUrlPreviewInE2EEChat, isFalse);
    });
  });
}
