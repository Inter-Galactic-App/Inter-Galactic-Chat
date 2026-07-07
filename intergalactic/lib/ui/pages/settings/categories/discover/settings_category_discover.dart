import 'package:flutter/material.dart';
import 'package:intergalactic/ui/pages/settings/categories/discover/discover_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:intl/intl.dart';

class SettingsCategoryDiscover implements SettingsCategory {
  static const tabIdDiscover = 'discover.server';

  String get labelSettingsCategoryDiscover => Intl.message(
        'Discover',
        name: 'labelSettingsCategoryDiscover',
        desc: 'Label for the Discover settings category',
      );

  @override
  String get title => labelSettingsCategoryDiscover;

  @override
  List<SettingsTab> get tabs => [
        SettingsTab(
          id: tabIdDiscover,
          label: labelSettingsCategoryDiscover,
          icon: Icons.travel_explore_outlined,
          searchKeywords: const [
            'discover',
            'server discovery',
            'room directory',
            'public rooms',
            'public spaces',
            'homeserver',
            'join rooms',
            'join spaces',
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: 'Discover rooms and spaces',
              section: 'Discover',
              keywords: [
                'server discovery',
                'room directory',
                'public rooms',
                'public spaces',
                'homeserver',
              ],
            ),
          ],
          pageBuilder: (context) => const DiscoverSettingsPage(),
        ),
      ];
}
