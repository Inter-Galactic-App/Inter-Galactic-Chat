import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/generated/intl/messages_all.dart';
import 'package:intergalactic/ui/pages/settings/categories/about/settings_category_about.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/general_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/shortcut_settings/keyboard_hook_shortcuts_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:intergalactic/ui/pages/settings/settings_search.dart';

void main() {
  test('general settings owns moved phase 2 keywords', () {
    final tabs = SettingsCategoryApp().tabs;
    final general = tabs.firstWhere((tab) => tab.label == 'General');

    expect(general.searchKeywords, contains('gif api key'));
    expect(general.searchKeywords, contains('gif relay'));
    expect(general.searchKeywords, contains('media previews'));
    expect(general.searchKeywords, contains('sticker compatibility'));
    expect(general.searchKeywords, contains('direct message lock'));
    expect(general.searchKeywords, contains('read receipts'));
    expect(general.searchKeywords, contains('typing indicator'));
    expect(general.searchKeywords, contains('minimize'));
  });

  test('public release media readiness rows stay searchable', () {
    final category = SettingsCategoryApp();

    final gifResults = filterSettingsCategories([category], 'approved relay');
    final gif = gifResults.single.tabs.single.entries.single;
    expect(gif.title, 'GIF search');
    expect(gif.description, contains('managed relay'));

    final previewResults = filterSettingsCategories([
      category,
    ], 'preview service');
    final preview = previewResults.single.tabs.single.entries.single;
    expect(preview.title, 'URL Preview in Encrypted Chats');
    expect(preview.description, contains('configured preview service'));
  });

  test('general settings exposes phase 7 row-level search aliases', () {
    final category = SettingsCategoryApp();
    final results = filterSettingsCategories([category], 'privacy');
    final general = results.single.tabs.firstWhere(
      (match) => match.tab.label == 'General',
    );

    expect(
      general.entries.map((entry) => entry.title),
      containsAll(['Read receipts', 'Typing indicator']),
    );
  });

  test('automatic message effects row is searchable', () {
    final category = SettingsCategoryApp();
    final results = filterSettingsCategories([category], 'snow day');
    final general = results.single.tabs.firstWhere(
      (match) => match.tab.label == 'General',
    );

    expect(
      general.entries.map((entry) => entry.title),
      contains('Automatic message effects'),
    );
  });

  test('story auto-download row is searchable', () {
    final category = SettingsCategoryApp();
    final results = filterSettingsCategories([category], 'iphone photos');
    final general = results.single.tabs.firstWhere(
      (match) => match.tab.label == 'General',
    );

    expect(
      general.entries.map((entry) => entry.title),
      contains('Auto-download story uploads'),
    );
  });

  test('old Window Behaviour label finds the moved window row', () {
    final results = filterSettingsCategories([
      SettingsCategoryApp(),
    ], 'Window Behaviour');
    final general = results.single.tabs.firstWhere(
      (match) => match.tab.label == 'General',
    );

    expect(general.entries.single.title, 'Minimize on close');
  });

  test('window behaviour is no longer a separate app settings tab', () {
    final labels = SettingsCategoryApp().tabs.map((tab) => tab.label).toList();

    expect(labels, isNot(contains('Window Behaviour')));
  });

  test('appearance settings owns moved phase 2 keywords', () {
    final tabs = SettingsCategoryApp().tabs;
    final appearance = tabs.firstWhere((tab) => tab.label == 'Appearance');

    expect(appearance.searchKeywords, contains('app icon'));
    expect(appearance.searchKeywords, contains('custom theme'));
    expect(appearance.searchKeywords, contains('export theme'));
    expect(appearance.searchKeywords, contains('app scale'));
    expect(appearance.searchKeywords, contains('text scale'));
    expect(appearance.searchKeywords, contains('small window'));
    expect(appearance.searchKeywords, contains('layout override'));
    expect(appearance.searchKeywords, contains('room avatars'));
  });

  test('accessibility settings exposes MVP row-level search aliases', () {
    final category = SettingsCategoryApp();
    final accessibility = category.tabs.firstWhere(
      (tab) => tab.label == 'Accessibility',
    );

    expect(accessibility.searchKeywords, contains('colorblind'));
    expect(accessibility.searchKeywords, contains('reduce motion'));
    expect(accessibility.searchKeywords, contains('reduce transparency'));
    expect(accessibility.searchKeywords, contains('persistent labels'));

    final results = filterSettingsCategories([
      category,
    ], 'pause animated media');
    final accessibilityMatch = results.single.tabs.firstWhere(
      (match) => match.tab.label == 'Accessibility',
    );

    expect(
      accessibilityMatch.entries.map((entry) => entry.title),
      contains('Pause animated media'),
    );

    final rowTitles = accessibility.searchEntries.map((entry) => entry.title);
    expect(
      rowTitles,
      containsAll([
        'Follow system',
        'Color mode',
        'Contrast',
        'Differentiate without color',
        'Underline links',
        'Strong focus indicators',
        'Show On/Off labels',
        'Reduce transparency',
        'Increase UI separation',
        'Text size',
        'Bold text',
        'Persistent action labels',
        'Motion',
        'Pause animated media',
        'Larger touch targets',
      ]),
    );
  });

  test('desktop companion owns companion keywords on Windows', () {
    final tabs = SettingsCategoryApp().tabs;
    final labels = tabs.map((tab) => tab.label).toList();

    if (!PlatformUtils.isWindows) {
      expect(labels, isNot(contains('Desktop Companion')));
      return;
    }

    final companion = tabs.firstWhere(
      (tab) => tab.label == 'Desktop Companion',
    );

    expect(companion.searchKeywords, contains('notification companion'));
    expect(companion.searchKeywords, contains('avatar'));
    expect(companion.searchKeywords, contains('reduced motion'));
  });

  test('mouse shortcut recording stays Windows-only', () {
    expect(debugCanRecordMouseShortcutsForTesting(isWindows: true), isTrue);
    expect(debugCanRecordMouseShortcutsForTesting(isWindows: false), isFalse);
    expect(
      debugShortcutRecorderInputSummaryForTesting(isWindows: true),
      contains('mouse'),
    );
    expect(
      debugShortcutRecorderInputSummaryForTesting(isWindows: false),
      isNot(contains('mouse')),
    );
  });

  test('phase 3 app settings labels are defined', () {
    final category = SettingsCategoryApp();

    expect(category.labelSettingsAppEmoticons, 'Emoticons');
    expect(category.labelSettingsAppSoundboard, 'Soundboard');
  });

  test('developer settings owns moved diagnostics keywords', () {
    final tabs = SettingsCategoryApp().tabs;
    final developer = tabs.firstWhere((tab) => tab.label == 'Developer');

    expect(developer.searchKeywords, contains('advanced'));
    expect(developer.searchKeywords, contains('webrtc'));
    expect(developer.searchKeywords, contains('stun'));
    expect(developer.searchKeywords, contains('rnnoise diagnostics'));
    expect(developer.searchKeywords, contains('advanced stream override'));
    expect(developer.searchKeywords, contains('adaptive fallback'));
    expect(developer.searchKeywords, contains('stream stats'));
    expect(developer.searchKeywords, contains('push transport'));
    expect(developer.searchKeywords, contains('registered pushers'));
    expect(developer.searchKeywords, contains('account json'));
    expect(developer.searchKeywords, contains('logs'));
    expect(developer.searchKeywords, contains('developer utils'));
    expect(developer.searchKeywords, contains('background tasks'));
  });

  test('old Advanced label finds Developer settings', () {
    final results = filterSettingsCategories([
      SettingsCategoryApp(),
    ], 'Advanced');
    final developer = results.single.tabs.firstWhere(
      (match) => match.tab.label == 'Developer',
    );

    expect(
      developer.entries.map((entry) => entry.title),
      contains('Developer mode'),
    );
  });

  test('developer tab label uses developer localization key', () async {
    await initializeMessages('en');
    Intl.defaultLocale = 'en';

    expect(SettingsCategoryApp().labelSettingsAppAdvanced, 'Developer');
  });

  test('phase 6 developer tools are consolidated under Developer', () {
    final appLabels = SettingsCategoryApp().tabs.map((tab) => tab.label);
    final aboutLabels = SettingsCategoryAbout().tabs.map((tab) => tab.label);

    expect(appLabels, isNot(contains('Developer Utils')));
    expect(aboutLabels, isNot(contains('Logs')));
  });

  test('notifications settings owns phase 5 keywords', () {
    final tabs = SettingsCategoryApp().tabs;
    final matchingTabs = tabs.where((tab) => tab.label == 'Notifications');
    expect(
      SettingsCategoryApp().labelSettingsAppNotifications,
      'Notifications',
    );

    if (matchingTabs.isEmpty) {
      return;
    }

    final notifications = matchingTabs.single;

    expect(notifications.searchKeywords, contains('notification mode'));
    expect(notifications.searchKeywords, contains('mentions'));
    expect(notifications.searchKeywords, contains('keywords'));
    expect(notifications.searchKeywords, contains('mute'));
    expect(notifications.searchKeywords, contains('overrides'));
    expect(
      notifications.searchKeywords,
      contains('room notification overrides'),
    );
    expect(
      notifications.searchKeywords,
      contains('space notification overrides'),
    );
  });

  test('voice and video settings exposes user-facing device keywords', () {
    final tabs = SettingsCategoryApp().tabs;
    final matchingTabs = tabs.where((tab) => tab.label == 'Voice and Video');
    if (matchingTabs.isEmpty) {
      return;
    }
    final voiceAndVideo = matchingTabs.single;

    expect(voiceAndVideo.searchKeywords, contains('camera test'));
    expect(voiceAndVideo.searchKeywords, contains('speaker volume'));
    expect(voiceAndVideo.searchKeywords, contains('microphone volume'));
    expect(voiceAndVideo.searchKeywords, contains('mic test'));
    expect(voiceAndVideo.searchKeywords, contains('push to talk'));
  });

  test(
    'general GIF API key copy does not collide with legacy translations',
    () async {
      await initializeMessages('en');
      Intl.defaultLocale = 'en';

      expect(
        GeneralSettingsPageState().labelGifSearchApiKeyDescription,
        contains('managed GIF relay'),
      );
    },
  );
}
