import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/settings_category_room.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The room's icon, name, topic and addresses had been filed under Admin
/// Settings. Everything in that section is readable by an ordinary member and
/// the topic is the main thing members open room settings to read, so filing it
/// under Admin hid it from its own audience. Owner report, 2026-09-03.
///
/// The search index is the half that is easy to forget: moving a section
/// without moving its `SettingsSearchEntry` leaves search sending people to the
/// tab the section is no longer on, which is worse than not indexing it at all.
/// Both directions are asserted here.
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

  List<dynamic> tabsForDemoRoom() {
    final room = client.getRoom(DemoClient.demoLoungeRoomId)!;
    return SettingsCategoryRoom(room, null).getTabs();
  }

  List<dynamic> tabsForMatrixRoom() {
    return SettingsCategoryRoom(_FakeMatrixRoom(), null).getTabs();
  }

  dynamic generalTabOf(List<dynamic> tabs) {
    return tabs.firstWhere(
      (tab) => tab.id == SettingsCategoryRoom.tabIdGeneral,
    );
  }

  test('room settings has a General tab, and it comes first', () {
    final tabs = tabsForDemoRoom();

    expect(tabs.first.id, SettingsCategoryRoom.tabIdGeneral);
    expect(tabs.first.label, 'General');
  });

  test('the profile entry is indexed under General for any room', () {
    final general = generalTabOf(tabsForDemoRoom());
    final titles = general.searchEntries.map((entry) => entry.title).toList();

    expect(titles, contains('Icon, name, and topic'));
    expect(
      general.searchKeywords,
      contains('topic'),
      reason: 'searching "topic" has to reach the tab the topic is now on',
    );
  });

  // `RoomGeneralSettingsPage` builds the Addresses section under
  // `if (room is MatrixRoom)`, so the index has to carry the same condition.
  // Search does not just open a tab - it names a control and scrolls to it -
  // so indexing a row the page will not build looks like broken search rather
  // than an absent feature. Asserted from both sides: a positive-only test
  // passes against an unconditional entry, which is what this was.
  group('the Addresses entry is indexed where the section is rendered', () {
    test('a Matrix room gets it', () {
      final general = generalTabOf(tabsForMatrixRoom());
      final titles = general.searchEntries.map((entry) => entry.title).toList();

      expect(titles, contains('Room Addresses'));
      expect(general.searchKeywords, contains('aliases'));
    });

    test('a non-Matrix room does not', () {
      final general = generalTabOf(tabsForDemoRoom());
      final titles = general.searchEntries.map((entry) => entry.title).toList();

      expect(titles, isNot(contains('Room Addresses')));
      expect(
        general.searchKeywords,
        isNot(contains('aliases')),
        reason:
            'the tab-level terms point at the same missing section as the '
            'entry, so gating only the entry would leave half the defect',
      );
    });
  });

  test('Admin no longer claims the profile or the addresses', () {
    final admin = tabsForDemoRoom().firstWhere(
      (tab) => tab.id == SettingsCategoryRoom.tabIdAdmin,
    );
    final titles = admin.searchEntries.map((entry) => entry.title).toList();

    expect(
      titles,
      isNot(contains('Icon, name, and topic')),
      reason:
          'a stale search entry would send a member searching for the topic '
          'back to Admin Settings, where the section no longer is',
    );
    expect(titles, isNot(contains('Room Addresses')));
    expect(admin.searchKeywords, isNot(contains('topic')));
    expect(admin.searchKeywords, isNot(contains('avatar')));

    // Admin keeps what genuinely belongs to it.
    expect(admin.searchKeywords, contains('server discovery'));
    expect(admin.searchKeywords, contains('room events'));
  });
}

/// Enough of a `MatrixRoom` for `getTabs()`, which reads components and
/// preferences and never builds a page. The demo client cannot supply this
/// side of the condition: `DemoRoom` is the non-Matrix case.
class _FakeMatrixRoom implements MatrixRoom {
  @override
  String get identifier => '!fake:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
