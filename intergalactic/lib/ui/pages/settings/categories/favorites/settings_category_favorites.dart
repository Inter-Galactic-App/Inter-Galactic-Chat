import 'package:flutter/material.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/ui/pages/settings/categories/favorites/favorites_appearance_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/favorites/favorites_categories_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:intl/intl.dart';

class SettingsCategoryFavorites implements SettingsCategory {
  SettingsCategoryFavorites({required this.clientManager});

  static const String tabIdAppearance = 'favorites.appearance';
  static const String tabIdCategories = 'favorites.categories';

  final ClientManager clientManager;

  String get labelFavoritesSettings => Intl.message(
    'Favorites Settings',
    name: 'labelFavoritesSettings',
    desc: 'Label for the overall Favorites settings category',
  );

  String get labelFavoritesAppearance => Intl.message(
    'Appearance',
    name: 'labelFavoritesSettingsAppearance',
    desc: 'Label for the Favorites appearance settings tab',
  );

  String get labelFavoritesCategories => Intl.message(
    'Categories',
    name: 'labelFavoritesSettingsCategories',
    desc: 'Label for the Favorites categories settings tab',
  );

  @override
  String? get title => labelFavoritesSettings;

  @override
  List<SettingsTab> get tabs => [
    SettingsTab(
      id: tabIdAppearance,
      label: labelFavoritesAppearance,
      icon: Icons.palette_outlined,
      searchKeywords: const [
        'favorites',
        'favorite rooms',
        'icon',
        'banner',
        'appearance',
      ],
      searchEntries: const [
        SettingsSearchEntry(
          title: 'Favorites icon',
          section: 'Appearance',
          keywords: ['avatar', 'rail icon', 'star'],
        ),
        SettingsSearchEntry(
          title: 'Favorites banner',
          section: 'Appearance',
          keywords: ['header', 'background'],
        ),
      ],
      pageBuilder: (context) => const FavoritesAppearanceSettingsPage(),
    ),
    SettingsTab(
      id: tabIdCategories,
      label: labelFavoritesCategories,
      icon: Icons.folder_copy_outlined,
      searchKeywords: const [
        'favorites',
        'favorite rooms',
        'categories',
        'groups',
        'homeservers',
        'accounts',
      ],
      searchEntries: const [
        SettingsSearchEntry(
          title: 'Favorites categories',
          section: 'Categories',
          keywords: [
            'groups',
            'rooms',
            'homeservers',
            'accounts',
            'local layout',
          ],
        ),
      ],
      pageBuilder: (context) =>
          FavoritesCategoriesSettingsPage(clientManager: clientManager),
    ),
  ];
}
