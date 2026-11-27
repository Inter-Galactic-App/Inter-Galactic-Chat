import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/discover/settings_category_discover.dart';
import 'package:intergalactic/ui/pages/settings/settings_search.dart';

void main() {
  test('Discover settings category exposes independent settings tab', () {
    final category = SettingsCategoryDiscover();
    final tab = category.tabs.single;

    expect(category.title, 'Discover');
    expect(tab.id, SettingsCategoryDiscover.tabIdDiscover);
    expect(tab.label, 'Discover');
    expect(tab.searchKeywords, contains('server discovery'));
  });

  test('Discover tab is searchable by room directory aliases', () {
    final results = filterSettingsCategories(
      [SettingsCategoryDiscover()],
      'public spaces',
    );

    expect(results.single.tabs.single.tab.label, 'Discover');
  });
}
