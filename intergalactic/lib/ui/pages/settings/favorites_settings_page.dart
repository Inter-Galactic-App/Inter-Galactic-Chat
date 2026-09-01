import 'package:flutter/material.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/ui/pages/settings/categories/favorites/settings_category_favorites.dart';
import 'package:intergalactic/ui/pages/settings/settings_page.dart';

class FavoritesSettingsPage extends StatelessWidget {
  const FavoritesSettingsPage({
    required this.clientManager,
    this.initialTabId,
    super.key,
  });

  final ClientManager clientManager;
  final String? initialTabId;

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      initialTabId: initialTabId,
      settings: [
        SettingsCategoryFavorites(clientManager: clientManager),
      ],
    );
  }
}
