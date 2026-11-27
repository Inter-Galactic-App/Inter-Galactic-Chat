import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/account_deletion_handoff.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/settings_category_account.dart';
import 'package:intergalactic/ui/pages/settings/settings_search.dart';

void main() {
  test('account category starts with Account & Profile', () {
    final labels =
        SettingsCategoryAccount().tabs.map((tab) => tab.label).toList();

    expect(labels.first, 'Account & Profile');
    expect(labels, isNot(contains('Manage Accounts')));
    expect(labels, isNot(contains('Profile')));
    expect(labels, isNot(contains('Privacy')));
    expect(labels, isNot(contains('Emoticons')));
    expect(labels, isNot(contains('Developer')));
    expect(labels, contains('Security'));
  });

  test('moved account settings keep old labels searchable', () {
    final tabs = SettingsCategoryAccount().tabs;
    final accountProfile = tabs.firstWhere(
      (tab) => tab.label == 'Account & Profile',
    );
    final security = tabs.firstWhere((tab) => tab.label == 'Security');

    expect(accountProfile.makeScrollable, isFalse);
    expect(accountProfile.searchKeywords, contains('manage accounts'));
    expect(accountProfile.searchKeywords, contains('profile'));
    expect(accountProfile.searchKeywords, contains('pronouns'));
    expect(security.searchKeywords, contains('account deletion'));
    expect(security.searchKeywords, contains('delete account'));
    expect(security.searchKeywords, contains('account deletion guide'));
  });

  test('old Manage Accounts label finds Account and Profile row', () {
    final results = filterSettingsCategories(
      [SettingsCategoryAccount()],
      'Manage Accounts',
    );
    final accountProfile = results.single.tabs.single;

    expect(accountProfile.tab.label, 'Account & Profile');
    expect(accountProfile.entries.single.title, 'Selected account');
  });

  test('account deletion guide is searchable from security settings', () {
    final results = filterSettingsCategories(
      [SettingsCategoryAccount()],
      'public guide',
    );
    final security = results.single.tabs.single;

    expect(security.tab.label, 'Security');
    expect(security.entries.single.title, 'Account Deletion');
    expect(
      security.entries.single.description,
      contains('public account-deletion guide'),
    );
  });

  test('account deletion homeserver help opens user-facing Matrix server name',
      () {
    final homeserver = homeserverWebsiteFromMatrixSession(
      userId: '@alice:matrix.org',
      homeserver: Uri.parse('https://matrix-client.matrix.org'),
      baseUri: null,
    );

    expect(homeserver, Uri.parse('https://matrix.org'));
  });

  test('account deletion homeserver help rewrites matrix.org API fallback', () {
    final homeserver = homeserverWebsiteFromMatrixSession(
      userId: null,
      homeserver: Uri.parse(
        'https://matrix-client.matrix.org/_matrix/client/v3',
      ),
      baseUri: null,
    );

    expect(homeserver, Uri.parse('https://matrix.org'));
  });

  test('account deletion homeserver help preserves custom server scheme', () {
    final homeserver = homeserverWebsiteFromMatrixSession(
      userId: '@alice:localhost:8008',
      homeserver: Uri.parse('http://localhost:8008'),
      baseUri: null,
    );

    expect(homeserver, Uri.parse('http://localhost:8008'));
  });

  test('account deletion homeserver help falls back to launchable API origin',
      () {
    final homeserver = homeserverWebsiteFromMatrixSession(
      userId: null,
      homeserver: Uri.parse('https://synapse.example.org:8448'),
      baseUri: null,
    );

    expect(homeserver, Uri.parse('https://synapse.example.org:8448'));
  });
}
