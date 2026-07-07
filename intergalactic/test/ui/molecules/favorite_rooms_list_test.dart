import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/favorite_rooms_list.dart';
import 'package:intergalactic/ui/pages/settings/categories/favorites/settings_category_favorites.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
  });

  testWidgets('wide header uses a space summary surface', (tester) async {
    final clientManager = ClientManager();
    addTearDown(clientManager.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            child: FavoriteRoomsList(
              clientManager: clientManager,
              showHeader: true,
              header: 'Favorites',
              emptyMessage: 'No favorites yet.',
            ),
          ),
        ),
      ),
    );
    // pumpAndSettle hangs here: the summary surface hosts a perpetual
    // animation, so pump bounded frames instead. Timing is driven by the
    // test binding's fake clock, so this cannot flake under CI load.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('Welcome to'), findsOneWidget);
    // Big title, star-row label, and summary panel header all say Favorites.
    expect(find.text('Favorites'), findsNWidgets(3));
    expect(find.text('Favorite rooms'), findsNothing);
    expect(find.text('0 rooms'), findsOneWidget);
    expect(find.text('No favorites yet.'), findsOneWidget);
    expect(find.byIcon(Icons.photo), findsNothing);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('narrow header does not add a visual parent category', (
    tester,
  ) async {
    final clientManager = ClientManager();
    addTearDown(clientManager.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: FavoriteRoomsList(
              clientManager: clientManager,
              showHeader: true,
              header: 'Favorites',
              emptyMessage: 'No favorites yet.',
            ),
          ),
        ),
      ),
    );
    // Bounded pumps for the same perpetual-animation reason as above.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('Welcome to'), findsNothing);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('No favorites yet.'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.byIcon(Icons.photo), findsNothing);
  });

  test('favorites settings exposes appearance and categories tabs', () {
    final clientManager = ClientManager();
    addTearDown(clientManager.close);

    final category = SettingsCategoryFavorites(clientManager: clientManager);
    final tabIds = category.tabs.map((tab) => tab.id).toList();

    expect(category.title, 'Favorites Settings');
    expect(tabIds, contains(SettingsCategoryFavorites.tabIdAppearance));
    expect(tabIds, contains(SettingsCategoryFavorites.tabIdCategories));
  });
}
