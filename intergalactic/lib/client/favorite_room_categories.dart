import 'package:intergalactic/client/space_room_categories.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String favoriteRoomCategoriesLocalId = '__favorites_virtual_space__';
const String favoriteRoomDefaultCategoryId = '__favorites_default_category__';
const String favoriteRoomDefaultCategoryName = 'Favorites';
const String _favoriteRoomStarterCategoryInitializedKey =
    'favorites.category_starter_initialized';
const String _favoriteRoomStarterCategoryRecoveredKey =
    'favorites.category_starter_recovered';
const Set<String> _legacyFavoriteRoomDefaultCategoryNames = {
  'favorite room',
  'favorite rooms',
  'favorite room(s)',
};

Future<void> _favoriteRoomStarterSeedQueue = Future<void>.value();

Future<SpaceRoomCategoryState> loadFavoriteRoomCategoryState({
  Iterable<String> favoriteRoomIds = const [],
}) async {
  final result = _favoriteRoomStarterSeedQueue.then(
    (_) => _loadFavoriteRoomCategoryStateUnqueued(
      favoriteRoomIds: favoriteRoomIds,
    ),
  );
  _favoriteRoomStarterSeedQueue = result.then<void>((_) {}, onError: (_) {});
  return result;
}

Future<SpaceRoomCategoryState> _loadFavoriteRoomCategoryStateUnqueued({
  required Iterable<String> favoriteRoomIds,
}) async {
  final state = await spaceRoomCategoryStore.load(
    favoriteRoomCategoriesLocalId,
  );
  final preferences = await SharedPreferences.getInstance();
  if (state.hasPersistedState) {
    final migratedState = _migrateFavoriteRoomCategoryState(state);
    if (!identical(migratedState, state)) {
      await saveFavoriteRoomCategoryState(migratedState);
    }
    await preferences.setBool(_favoriteRoomStarterCategoryInitializedKey, true);
    await preferences.setBool(_favoriteRoomStarterCategoryRecoveredKey, true);
    return migratedState;
  }

  final seededRoomIds = favoriteRoomIds.toSet().toList(growable: false);
  if (seededRoomIds.isEmpty) {
    return state;
  }
  final starterInitialized =
      preferences.getBool(_favoriteRoomStarterCategoryInitializedKey) == true;
  final starterRecovered =
      preferences.getBool(_favoriteRoomStarterCategoryRecoveredKey) == true;
  if (starterInitialized && starterRecovered) {
    return state;
  }

  final starterState = SpaceRoomCategoryState(
    categories: [
      SpaceRoomCategoryDefinition(
        id: favoriteRoomDefaultCategoryId,
        name: favoriteRoomDefaultCategoryName,
        roomIds: seededRoomIds,
        roomOrderIds: seededRoomIds,
      ),
    ],
  );
  await saveFavoriteRoomCategoryState(starterState);
  await preferences.setBool(_favoriteRoomStarterCategoryInitializedKey, true);
  await preferences.setBool(_favoriteRoomStarterCategoryRecoveredKey, true);
  return starterState;
}

Future<void> saveFavoriteRoomCategoryState(SpaceRoomCategoryState state) {
  return spaceRoomCategoryStore.save(favoriteRoomCategoriesLocalId, state);
}

SpaceRoomCategoryState _migrateFavoriteRoomCategoryState(
  SpaceRoomCategoryState state,
) {
  if (state.categories.isEmpty) {
    return state;
  }

  var changed = false;
  var favoriteCategoryIndex = -1;
  final categories = <SpaceRoomCategoryDefinition>[];

  for (final category in state.categories) {
    final isDefaultCategory =
        _isLegacyFavoriteRoomDefaultCategoryName(category.name) ||
        category.name.trim().toLowerCase() ==
            favoriteRoomDefaultCategoryName.toLowerCase();
    final migratedCategory = isDefaultCategory
        ? category.copyWith(name: favoriteRoomDefaultCategoryName)
        : category;

    if (migratedCategory.name != category.name) {
      changed = true;
    }

    if (migratedCategory.name == favoriteRoomDefaultCategoryName) {
      if (favoriteCategoryIndex == -1) {
        favoriteCategoryIndex = categories.length;
        categories.add(migratedCategory);
      } else {
        categories[favoriteCategoryIndex] = _mergeFavoriteCategories(
          categories[favoriteCategoryIndex],
          migratedCategory,
        );
        changed = true;
      }
      continue;
    }

    categories.add(migratedCategory);
  }

  return changed ? state.copyWith(categories: categories) : state;
}

bool _isLegacyFavoriteRoomDefaultCategoryName(String value) {
  return _legacyFavoriteRoomDefaultCategoryNames.contains(
    normalizeSpaceRoomCategoryName(value).toLowerCase(),
  );
}

SpaceRoomCategoryDefinition _mergeFavoriteCategories(
  SpaceRoomCategoryDefinition target,
  SpaceRoomCategoryDefinition source,
) {
  return target.copyWith(
    roomIds: _mergeUniqueStrings(target.roomIds, source.roomIds),
    roomOrderIds: _mergeUniqueStrings(target.roomOrderIds, source.roomOrderIds),
    collapsed: target.collapsed && source.collapsed,
  );
}

List<String> _mergeUniqueStrings(List<String> first, List<String> second) {
  final result = <String>[];
  for (final value in [...first, ...second]) {
    if (!result.contains(value)) {
      result.add(value);
    }
  }
  return result;
}
