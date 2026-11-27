import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/settings_category_space.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A space's icon, name, topic, banner and addresses had been filed under Admin
/// Settings. Everything in that section is readable by an ordinary member and
/// the topic is the main thing members open space settings to read, so filing
/// it under Admin hid it from its own audience. This mirrors the identical room
/// change on the same branch. Owner report, 2026-09-03.
///
/// The search index is the half that is easy to forget: moving a section
/// without moving its `SettingsSearchEntry` leaves search sending people to the
/// tab the section is no longer on, which is worse than not indexing it at all.
/// Both directions are asserted here.
///
/// The id split is the space-specific trap. `tabIdGeneral` used to be an alias
/// for `tabIdNotifications` ('space.general'), so General and Notifications were
/// the same id. They are now distinct, and the two constants must not collide
/// again or deep links break.
void main() {
  late DemoClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = DemoClient.createOfflineDemo();
    await client.init(false);
  });

  tearDown(() async {
    await client.close();
  });

  List<dynamic> tabsForDemoSpace() {
    final space = client.getSpace(DemoClient.demoSpaceId)!;
    return SettingsCategorySpace(space).getTabs();
  }

  test('General and Notifications are distinct tab ids', () {
    expect(
      SettingsCategorySpace.tabIdGeneral,
      isNot(SettingsCategorySpace.tabIdNotifications),
      reason:
          'these were aliased to the same string; a regression that re-merges '
          'them sends the General tab and the notification deep link to one '
          'destination',
    );
  });

  test('space settings has a General tab, and it comes first', () {
    final tabs = tabsForDemoSpace();

    expect(tabs.first.id, SettingsCategorySpace.tabIdGeneral);
    expect(tabs.first.label, 'General');
  });

  test(
    'the profile, banner and addresses entries are indexed under General',
    () {
      final general = tabsForDemoSpace().firstWhere(
        (tab) => tab.id == SettingsCategorySpace.tabIdGeneral,
      );
      final titles = general.searchEntries.map((entry) => entry.title).toList();

      expect(titles, contains('Icon, name, and topic'));
      expect(titles, contains('Space banner'));
      expect(titles, contains('Room Addresses'));
      expect(
        general.searchKeywords,
        contains('topic'),
        reason: 'searching "topic" has to reach the tab the topic is now on',
      );
    },
  );

  test('Admin no longer claims the profile, banner or the addresses', () {
    final admin = tabsForDemoSpace().firstWhere(
      (tab) => tab.id == SettingsCategorySpace.tabIdAdmin,
    );
    final titles = admin.searchEntries.map((entry) => entry.title).toList();

    expect(
      titles,
      isNot(contains('Icon, name, and topic')),
      reason:
          'a stale search entry would send a member searching for the topic '
          'back to Admin Settings, where the section no longer is',
    );
    expect(titles, isNot(contains('Space banner')));
    expect(titles, isNot(contains('Room Addresses')));
    expect(admin.searchKeywords, isNot(contains('topic')));
    expect(admin.searchKeywords, isNot(contains('avatar')));
    expect(admin.searchKeywords, isNot(contains('banner')));

    // Admin keeps what genuinely belongs to it: who can join, and Discover.
    expect(titles, contains('Space Visibility'));
    expect(titles, contains('Discover listing'));
    expect(admin.searchKeywords, contains('server discovery'));
  });
}
