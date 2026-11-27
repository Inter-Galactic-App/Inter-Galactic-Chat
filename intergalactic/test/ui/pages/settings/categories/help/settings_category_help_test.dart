import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/public_release_links.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/settings_category_help.dart';
import 'package:intergalactic/ui/pages/settings/settings_search.dart';

void main() {
  test('policy tab exposes hosted public release links in search', () {
    final results = filterSettingsCategories(
      [SettingsCategoryHelp()],
      'source offer',
    );
    final policies = results.single.tabs.single;

    expect(policies.tab.label, 'Policies');
    expect(policies.entries.single.title, 'Source Offer');
    expect(PublicReleaseLinks.sourceUrl, 'https://app.ourgalaxy.space/source/');
  });

  test('help tab exposes website feedback link in search', () {
    final results = filterSettingsCategories(
      [SettingsCategoryHelp()],
      'usability feedback',
    );
    final safety = results.single.tabs.single;

    expect(safety.tab.label, 'Help & Safety');
    expect(safety.entries.single.title, 'Send feedback or request a feature');
    expect(
      PublicReleaseLinks.feedbackUrl,
      'https://app.ourgalaxy.space/feedback/',
    );
  });

  test('policy tab exposes hosted third-party notices in search', () {
    final results = filterSettingsCategories(
      [SettingsCategoryHelp()],
      'third-party notices',
    );
    final policies = results.single.tabs.single;

    expect(policies.tab.label, 'Policies');
    expect(policies.entries.single.title, 'Third-Party Notices');
    expect(
      PublicReleaseLinks.thirdPartyNoticesUrl,
      'https://app.ourgalaxy.space/third-party-notices/',
    );
  });

  test('all policy links use the hosted app site', () {
    expect(
      PublicReleaseLinks.policyLinks.map((link) => link.url),
      everyElement(startsWith('${PublicReleaseLinks.siteBaseUrl}/')),
    );
  });
}
