import 'dart:async';
import 'dart:convert';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/space_room_categories.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String favoriteRoomCategoriesLocalId = '__favorites_virtual_space__';
const String favoriteRoomDefaultCategoryId = '__favorites_default_category__';
const String favoriteRoomDefaultCategoryName = 'Favorites';
const String favoriteRoomCategoriesAccountDataType =
    'chat.intergalactic.favorite_categories.v1';
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
    LocalSpaceCategoryScope.favorites,
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
  return spaceRoomCategoryStore.save(LocalSpaceCategoryScope.favorites, state);
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

/// The account-wide counterpart to the local Favorites category preference.
///
/// Matrix has no standard category model, so this uses an Inter Galactic
/// versioned account-data event. It deliberately keeps each account's data
/// separate: a user with two accounts must never upload account A's room ids
/// into account B's account data.
class FavoriteRoomCategoryStore {
  final StreamController<FavoriteRoomCategoryChanged> _onChanged =
      StreamController.broadcast();
  final Map<
    String,
    ({SpaceRoomCategoryState state, SpaceRoomCategoryState? baseline})
  >
  _pending = {};
  final Set<String> _migrating = {};

  Stream<FavoriteRoomCategoryChanged> get onChanged => _onChanged.stream;

  Future<SpaceRoomCategoryState> load({
    required Client client,
    Iterable<String> favoriteRoomIds = const [],
  }) async {
    if (client is! MatrixClient || !_isReady(client)) {
      return _loadLocalFallback(client, favoriteRoomIds);
    }

    final pending = _pending[client.getMatrixClient().userID!];
    if (pending != null) return pending.state;

    final matrixClient = client.getMatrixClient();
    if (matrixClient.accountDataLoading != null) {
      await matrixClient.accountDataLoading;
    }
    final remote = _remoteState(client);
    if (remote != null) return _withLocalViewState(client, remote);

    // Only the completed-sync migration path writes account data. Until that
    // point an empty state renders safely without risking an overwrite of an
    // event that has not entered the SDK cache yet.
    return _stateForFavoriteIds(SpaceRoomCategoryState.empty, favoriteRoomIds);
  }

  /// Writes account data first. There is intentionally no local fallback: a
  /// category that only appears saved is the device-local behaviour this
  /// migration removes.
  Future<void> save({
    required Client client,
    required SpaceRoomCategoryState state,
  }) async {
    if (client is! MatrixClient || !_isReady(client)) {
      await spaceRoomCategoryStore.save(_localId(client), state);
      _emit(client, state);
      return;
    }

    final matrixClient = client.getMatrixClient();
    final userId = matrixClient.userID!;
    try {
      await matrixClient.setAccountData(
        userId,
        favoriteRoomCategoriesAccountDataType,
        state.toMatrixStateContent(),
      );
    } catch (error, trace) {
      Log.onError(error, trace, content: 'Failed to save favorite categories');
      rethrow;
    }

    await spaceRoomCategoryStore.save(_localId(client), state);
    _pending[userId] = (state: state, baseline: _remoteState(client));
    _emit(client, state);
  }

  /// Persists device-local presentation state without creating an account-data
  /// write. Collapse/expand is a view preference, so another device must not
  /// receive it or wait for an echo that can never contain the flag.
  Future<void> saveLocalView({
    required Client client,
    required SpaceRoomCategoryState state,
  }) async {
    await spaceRoomCategoryStore.save(_localId(client), state);
    _emit(client, state);
  }

  /// Re-read the SDK account-data cache after every client sync. A matching
  /// server echo settles an optimistic write; a remote edit on another device
  /// replaces the rendered category state.
  Future<void> onClientSync(Client client) async {
    if (client is! MatrixClient || !_isReady(client)) return;
    final userId = client.getMatrixClient().userID!;
    final remote = _remoteState(client);
    if (remote == null) return;

    final pending = _pending[userId];
    final resolution = resolveSyncedState(
      pending: pending?.state,
      remote: remote,
      baseline: pending?.baseline,
      baselineKnown: pending != null,
    );
    if (resolution.settlePending) {
      _pending.remove(userId);
    }
    if (pending != null && !resolution.settlePending) {
      // A sync can still contain the account-data value from before our
      // successful write. Keep the optimistic state visible until its exact
      // echo arrives; otherwise the picker visibly jumps backwards and the
      // next write can persist that stale value over the user's change.
      _emit(client, pending.state);
      return;
    }
    _emit(client, await _withLocalViewState(client, resolution.visible));
  }

  /// Resolves an account-data sync against a write that is waiting for its
  /// server echo. A differing value is not necessarily another device's edit:
  /// it may be the older value from a sync raced with our write.
  static ({SpaceRoomCategoryState visible, bool settlePending})
  resolveSyncedState({
    required SpaceRoomCategoryState? pending,
    required SpaceRoomCategoryState remote,
    SpaceRoomCategoryState? baseline,
    bool baselineKnown = false,
  }) {
    if (pending == null) {
      return (visible: remote, settlePending: false);
    }
    if (_sameStateValues(pending, remote)) {
      return (visible: remote, settlePending: true);
    }
    if (baselineKnown &&
        (baseline == null || !_sameStateValues(baseline, remote))) {
      return (visible: remote, settlePending: true);
    }
    return (visible: pending, settlePending: false);
  }

  /// Imports the former device-local state once account data has completed its
  /// first sync. Calling this separately from [load] avoids treating an empty
  /// pre-sync cache as proof that the server has no category event.
  Future<void> migrateClient(
    Client client, {
    Iterable<String> favoriteRoomIds = const [],
  }) async {
    if (client is! MatrixClient || !_isReady(client)) return;
    if (_remoteState(client) != null) return;

    final userId = client.getMatrixClient().userID!;
    final pending = _pending[userId];
    if (pending != null) {
      _emit(client, pending.state);
      return;
    }
    final state = await _migrateLegacyState(
      client: client,
      userId: userId,
      favoriteRoomIds: favoriteRoomIds,
    );
    if (state != null) _emit(client, state);
  }

  Future<SpaceRoomCategoryState?> _migrateLegacyState({
    required MatrixClient client,
    required String userId,
    required Iterable<String> favoriteRoomIds,
  }) async {
    if (preferences.isFavoriteRoomCategoriesMigrated(userId)) {
      return null;
    }
    if (!_migrating.add(userId)) return null;

    try {
      final legacy = await spaceRoomCategoryStore.load(
        LocalSpaceCategoryScope.favorites,
      );
      final scoped = _stateForFavoriteIds(legacy, favoriteRoomIds);
      if (!scoped.hasPersistedState) {
        await preferences.markFavoriteRoomCategoriesMigrated(userId);
        return scoped;
      }

      await save(client: client, state: scoped);
      await preferences.markFavoriteRoomCategoriesMigrated(userId);
      return scoped;
    } finally {
      _migrating.remove(userId);
    }
  }

  SpaceRoomCategoryState? _remoteState(MatrixClient client) {
    final rawContent = client
        .getMatrixClient()
        .accountData[favoriteRoomCategoriesAccountDataType]
        ?.content;
    if (rawContent is! Map) return null;
    return SpaceRoomCategoryState.fromMatrixStateContent(
      Map<String, Object?>.from(rawContent as Map<dynamic, dynamic>),
    );
  }

  Future<SpaceRoomCategoryState> _withLocalViewState(
    Client client,
    SpaceRoomCategoryState remote,
  ) async => remote.withLocalViewState(
    await spaceRoomCategoryStore.load(_localId(client)),
  );

  Future<SpaceRoomCategoryState> _loadLocalFallback(
    Client client,
    Iterable<String> favoriteRoomIds,
  ) async {
    final state = await spaceRoomCategoryStore.load(_localId(client));
    if (state.hasPersistedState) return state;
    return _stateForFavoriteIds(state, favoriteRoomIds);
  }

  SpaceRoomCategoryState _stateForFavoriteIds(
    SpaceRoomCategoryState state,
    Iterable<String> favoriteRoomIds,
  ) {
    final ids = favoriteRoomIds.toSet();
    final scoped = state.normalizedForRoomIds(ids);
    if (scoped.hasPersistedState || ids.isEmpty) return scoped;
    return SpaceRoomCategoryState(
      categories: [
        SpaceRoomCategoryDefinition(
          id: favoriteRoomDefaultCategoryId,
          name: favoriteRoomDefaultCategoryName,
          roomIds: ids.toList(growable: false),
          roomOrderIds: ids.toList(growable: false),
        ),
      ],
    );
  }

  bool _isReady(MatrixClient client) {
    final userId = client.getMatrixClient().userID;
    return userId != null && userId.isNotEmpty;
  }

  LocalSpaceCategoryScope _localId(Client client) =>
      LocalSpaceCategoryScope.forClient(
        '$favoriteRoomCategoriesLocalId.${client.identifier}',
      );

  static bool _sameStateValues(
    SpaceRoomCategoryState a,
    SpaceRoomCategoryState b,
  ) =>
      jsonEncode(a.toMatrixStateContent()) ==
      jsonEncode(b.toMatrixStateContent());

  void _emit(Client client, SpaceRoomCategoryState state) =>
      _onChanged.add(FavoriteRoomCategoryChanged(client: client, state: state));

  void clearForTesting() {
    _pending.clear();
    _migrating.clear();
  }
}

class FavoriteRoomCategoryChanged {
  const FavoriteRoomCategoryChanged({
    required this.client,
    required this.state,
  });

  final Client client;
  final SpaceRoomCategoryState state;
}

final favoriteRoomCategoryStore = FavoriteRoomCategoryStore();
