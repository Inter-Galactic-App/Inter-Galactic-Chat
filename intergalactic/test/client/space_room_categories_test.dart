import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/favorite_room_categories.dart';
import 'package:intergalactic/client/space_room_categories.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists local fallback category state per space', () async {
    final prefs = await SharedPreferences.getInstance();
    var idCount = 0;
    final store = SpaceRoomCategoryStore(
      preferences: prefs,
      idFactory: () => 'category-${++idCount}',
    );
    addTearDown(store.dispose);

    final changes = <SpaceRoomCategoryChanged>[];
    final subscription = store.onChanged.listen(changes.add);
    addTearDown(subscription.cancel);

    final category = await store.createCategory(
      LocalSpaceCategoryScope.forTesting('client-a:!space:server'),
      '  Raid   Rooms  ',
    );
    await store.assignRoomToCategory(
      LocalSpaceCategoryScope.forTesting('client-a:!space:server'),
      '!general:server',
      category.id,
    );

    final state = await store.load(
      LocalSpaceCategoryScope.forTesting('client-a:!space:server'),
    );
    final otherState = await store.load(
      LocalSpaceCategoryScope.forTesting('client-b:!space:server'),
    );

    expect(state.categories, hasLength(1));
    expect(state.categories.single.name, 'Raid Rooms');
    expect(state.categories.single.roomIds, ['!general:server']);
    expect(otherState.categories, isEmpty);
    expect(changes.map((change) => change.spaceLocalId).toSet(), {
      LocalSpaceCategoryScope.forTesting('client-a:!space:server'),
    });
  });

  test('persists uncategorized-only room order state per space', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = SpaceRoomCategoryStore(preferences: prefs);
    addTearDown(store.dispose);

    await store.save(
      LocalSpaceCategoryScope.forTesting('client-a:!space:server'),
      const SpaceRoomCategoryState(
        uncategorizedRoomOrderIds: ['!two:server', '!one:server'],
      ),
    );

    final state = await store.load(
      LocalSpaceCategoryScope.forTesting('client-a:!space:server'),
    );
    final otherState = await store.load(
      LocalSpaceCategoryScope.forTesting('client-b:!space:server'),
    );

    expect(state.categories, isEmpty);
    expect(state.uncategorizedCollapsed, isFalse);
    expect(state.uncategorizedRoomOrderIds, ['!two:server', '!one:server']);
    expect(otherState, SpaceRoomCategoryState.empty);
  });

  test('seeds editable Favorites category only once', () async {
    final seededState = await loadFavoriteRoomCategoryState(
      favoriteRoomIds: ['!two:server', '!one:server', '!two:server'],
    );

    expect(seededState.categories, hasLength(1));
    expect(seededState.categories.single.id, favoriteRoomDefaultCategoryId);
    expect(seededState.categories.single.name, favoriteRoomDefaultCategoryName);
    expect(seededState.categories.single.roomIds, [
      '!two:server',
      '!one:server',
    ]);
    expect(seededState.categories.single.roomOrderIds, [
      '!two:server',
      '!one:server',
    ]);

    await saveFavoriteRoomCategoryState(SpaceRoomCategoryState.empty);

    final reloadedState = await loadFavoriteRoomCategoryState(
      favoriteRoomIds: ['!three:server'],
    );
    expect(reloadedState.categories, isEmpty);
  });

  test('defers editable Favorites category seed until rooms exist', () async {
    final emptyState = await loadFavoriteRoomCategoryState();

    expect(emptyState, SpaceRoomCategoryState.empty);

    final seededState = await loadFavoriteRoomCategoryState(
      favoriteRoomIds: ['!first:server'],
    );

    expect(seededState.categories, hasLength(1));
    expect(seededState.categories.single.id, favoriteRoomDefaultCategoryId);
    expect(seededState.categories.single.roomIds, ['!first:server']);
  });

  test(
    'recovers initialized Favorites starter missing from category storage',
    () async {
      SharedPreferences.setMockInitialValues({
        'favorites.category_starter_initialized': true,
      });

      final recoveredState = await loadFavoriteRoomCategoryState(
        favoriteRoomIds: ['!first:server'],
      );

      expect(recoveredState.categories, hasLength(1));
      expect(
        recoveredState.categories.single.id,
        favoriteRoomDefaultCategoryId,
      );
      expect(
        recoveredState.categories.single.name,
        favoriteRoomDefaultCategoryName,
      );
      expect(recoveredState.categories.single.roomIds, ['!first:server']);

      await saveFavoriteRoomCategoryState(SpaceRoomCategoryState.empty);

      final deletedState = await loadFavoriteRoomCategoryState(
        favoriteRoomIds: ['!second:server'],
      );

      expect(deletedState.categories, isEmpty);
    },
  );

  test('respects renamed editable Favorites starter category', () async {
    await loadFavoriteRoomCategoryState(favoriteRoomIds: ['!first:server']);

    await spaceRoomCategoryStore.renameCategory(
      LocalSpaceCategoryScope.favorites,
      favoriteRoomDefaultCategoryId,
      'Pinned Across Accounts',
    );

    final reloadedState = await loadFavoriteRoomCategoryState(
      favoriteRoomIds: ['!first:server'],
    );

    expect(reloadedState.categories, hasLength(1));
    expect(reloadedState.categories.single.id, favoriteRoomDefaultCategoryId);
    expect(reloadedState.categories.single.name, 'Pinned Across Accounts');
    expect(reloadedState.categories.single.roomIds, ['!first:server']);
  });

  test(
    'normalizes stale Favorite room category without rewriting rename',
    () async {
      await saveFavoriteRoomCategoryState(
        const SpaceRoomCategoryState(
          categories: [
            SpaceRoomCategoryDefinition(
              id: favoriteRoomDefaultCategoryId,
              name: 'Pinned Across Accounts',
              roomIds: ['!first:server'],
              roomOrderIds: ['!first:server'],
            ),
            SpaceRoomCategoryDefinition(
              id: 'legacy-favorite-room',
              name: 'Favorite room(s)',
              roomIds: ['!second:server'],
              roomOrderIds: ['!second:server'],
            ),
            SpaceRoomCategoryDefinition(
              id: 'duplicate-favorites',
              name: 'favorites',
              roomIds: ['!third:server'],
              roomOrderIds: ['!third:server'],
            ),
          ],
        ),
      );

      final migratedState = await loadFavoriteRoomCategoryState(
        favoriteRoomIds: ['!first:server', '!second:server', '!third:server'],
      );

      expect(migratedState.categories, hasLength(2));
      expect(migratedState.categories[0].id, favoriteRoomDefaultCategoryId);
      expect(migratedState.categories[0].name, 'Pinned Across Accounts');
      expect(migratedState.categories[0].roomIds, ['!first:server']);
      expect(migratedState.categories[1].name, favoriteRoomDefaultCategoryName);
      expect(migratedState.categories[1].roomIds, [
        '!second:server',
        '!third:server',
      ]);
      expect(migratedState.categories[1].roomOrderIds, [
        '!second:server',
        '!third:server',
      ]);
    },
  );

  test('Matrix state content excludes local collapse state', () {
    const state = SpaceRoomCategoryState(
      categories: [
        SpaceRoomCategoryDefinition(
          id: 'alpha',
          name: 'Alpha',
          roomIds: ['!one:server'],
          roomOrderIds: ['!one:server'],
          collapsed: true,
        ),
      ],
      uncategorizedCollapsed: true,
      uncategorizedRoomOrderIds: ['!two:server'],
    );

    expect(state.toMatrixStateContent(), {
      'version': 1,
      'categories': [
        {
          'id': 'alpha',
          'name': 'Alpha',
          'room_ids': ['!one:server'],
          'room_order_ids': ['!one:server'],
        },
      ],
      'uncategorized_room_order_ids': ['!two:server'],
    });

    final parsed = SpaceRoomCategoryState.fromMatrixStateContent({
      'categories': [
        {
          'id': 'alpha',
          'name': 'Alpha',
          'room_ids': ['!one:server'],
          'room_order_ids': ['!one:server'],
          'collapsed': true,
        },
      ],
      'uncategorized_collapsed': true,
      'uncategorized_room_order_ids': ['!two:server'],
    });

    expect(parsed.categories.single.collapsed, isFalse);
    expect(parsed.categories.single.roomOrderIds, ['!one:server']);
    expect(parsed.uncategorizedCollapsed, isFalse);
    expect(parsed.uncategorizedRoomOrderIds, ['!two:server']);
  });

  test('category sync keeps pending state until its write echo arrives', () {
    const pending = SpaceRoomCategoryState(
      categories: [SpaceRoomCategoryDefinition(id: 'alpha', name: 'Alpha')],
    );
    const staleRemote = SpaceRoomCategoryState(
      categories: [SpaceRoomCategoryDefinition(id: 'legacy', name: 'Legacy')],
    );

    final stale = FavoriteRoomCategoryStore.resolveSyncedState(
      pending: pending,
      remote: staleRemote,
    );
    expect(stale.visible, pending);
    expect(stale.settlePending, isFalse);

    final echo = FavoriteRoomCategoryStore.resolveSyncedState(
      pending: pending,
      remote: pending,
    );
    expect(echo.visible, pending);
    expect(echo.settlePending, isTrue);
  });

  test('category sync accepts a post-write remote edit', () {
    const pending = SpaceRoomCategoryState(
      categories: [SpaceRoomCategoryDefinition(id: 'local', name: 'Local')],
    );
    const baseline = SpaceRoomCategoryState(
      categories: [SpaceRoomCategoryDefinition(id: 'old', name: 'Old')],
    );
    const remote = SpaceRoomCategoryState(
      categories: [SpaceRoomCategoryDefinition(id: 'other', name: 'Other')],
    );

    final stale = FavoriteRoomCategoryStore.resolveSyncedState(
      pending: pending,
      remote: baseline,
      baseline: baseline,
      baselineKnown: true,
    );
    expect(stale.visible, pending);
    expect(stale.settlePending, isFalse);

    final edit = FavoriteRoomCategoryStore.resolveSyncedState(
      pending: pending,
      remote: remote,
      baseline: baseline,
      baselineKnown: true,
    );
    expect(edit.visible, remote);
    expect(edit.settlePending, isTrue);
  });

  test('category sync settles a collapsed local view on the shared echo', () {
    const pending = SpaceRoomCategoryState(
      categories: [
        SpaceRoomCategoryDefinition(
          id: 'alpha',
          name: 'Alpha',
          roomIds: ['!one:server'],
          roomOrderIds: ['!one:server'],
          collapsed: true,
        ),
      ],
    );
    final remote = SpaceRoomCategoryState.fromMatrixStateContent(
      pending.toMatrixStateContent(),
    );

    final resolution = FavoriteRoomCategoryStore.resolveSyncedState(
      pending: pending,
      remote: remote,
    );

    expect(resolution.settlePending, isTrue);
    expect(resolution.visible.categories.single.collapsed, isFalse);
  });

  test('category sync accepts remote edits after no write is pending', () {
    const remote = SpaceRoomCategoryState(
      categories: [SpaceRoomCategoryDefinition(id: 'remote', name: 'Remote')],
    );

    final resolved = FavoriteRoomCategoryStore.resolveSyncedState(
      pending: null,
      remote: remote,
    );
    expect(resolved.visible, remote);
    expect(resolved.settlePending, isFalse);
  });

  test('local viewer collapse state merges into shared definitions', () {
    const sharedState = SpaceRoomCategoryState(
      categories: [
        SpaceRoomCategoryDefinition(
          id: 'alpha',
          name: 'Alpha',
          roomIds: ['!one:server'],
        ),
        SpaceRoomCategoryDefinition(
          id: 'beta',
          name: 'Beta',
          roomIds: ['!two:server'],
        ),
      ],
    );
    const localViewState = SpaceRoomCategoryState(
      categories: [
        SpaceRoomCategoryDefinition(id: 'beta', name: 'Beta', collapsed: true),
      ],
      uncategorizedCollapsed: true,
    );

    final merged = sharedState.withLocalViewState(localViewState);

    expect(merged.categories[0].collapsed, isFalse);
    expect(merged.categories[1].collapsed, isTrue);
    expect(merged.categories[1].roomIds, ['!two:server']);
    expect(merged.uncategorizedCollapsed, isTrue);
  });

  test('assigning a room moves it out of the previous category', () async {
    final prefs = await SharedPreferences.getInstance();
    final ids = ['alpha', 'beta'].iterator;
    final store = SpaceRoomCategoryStore(
      preferences: prefs,
      idFactory: () {
        ids.moveNext();
        return ids.current;
      },
    );
    addTearDown(store.dispose);

    final alpha = await store.createCategory(
      LocalSpaceCategoryScope.forTesting('client:!space'),
      'Alpha',
    );
    final beta = await store.createCategory(
      LocalSpaceCategoryScope.forTesting('client:!space'),
      'Beta',
    );

    await store.assignRoomToCategory(
      LocalSpaceCategoryScope.forTesting('client:!space'),
      '!room:server',
      alpha.id,
    );
    await store.assignRoomToCategory(
      LocalSpaceCategoryScope.forTesting('client:!space'),
      '!room:server',
      beta.id,
    );

    final state = await store.load(
      LocalSpaceCategoryScope.forTesting('client:!space'),
    );

    expect(state.categories[0].roomIds, isEmpty);
    expect(state.categories[1].roomIds, ['!room:server']);
  });

  test('groups categorized rooms and leaves the rest uncategorized', () {
    final state = SpaceRoomCategoryState(
      categories: const [
        SpaceRoomCategoryDefinition(
          id: 'alpha',
          name: 'Alpha',
          roomIds: ['!two:server', '!missing:server'],
        ),
        SpaceRoomCategoryDefinition(
          id: 'beta',
          name: 'Beta',
          roomIds: ['!one:server', '!two:server'],
          collapsed: true,
        ),
      ],
      uncategorizedCollapsed: true,
    );

    final groups = buildSpaceRoomCategoryGroups<String>(
      state: state,
      rooms: ['!one:server', '!two:server', '!three:server'],
      roomId: (roomId) => roomId,
    );

    expect(groups, hasLength(3));
    expect(groups[0].name, 'Alpha');
    expect(groups[0].rooms, ['!two:server']);
    expect(groups[1].name, 'Beta');
    expect(groups[1].rooms, ['!one:server']);
    expect(groups[1].collapsed, isTrue);
    expect(groups[2].isUncategorized, isTrue);
    expect(groups[2].rooms, ['!three:server']);
    expect(groups[2].collapsed, isTrue);
  });

  test('groups preserve the current space child order within categories', () {
    const state = SpaceRoomCategoryState(
      categories: [
        SpaceRoomCategoryDefinition(
          id: 'alpha',
          name: 'Alpha',
          roomIds: ['!two:server', '!one:server'],
        ),
        SpaceRoomCategoryDefinition(
          id: 'beta',
          name: 'Beta',
          roomIds: ['!four:server', '!three:server'],
        ),
      ],
    );

    final groups = buildSpaceRoomCategoryGroups<String>(
      state: state,
      rooms: ['!one:server', '!three:server', '!two:server', '!four:server'],
      roomId: (roomId) => roomId,
    );

    expect(groups[0].rooms, ['!one:server', '!two:server']);
    expect(groups[1].rooms, ['!three:server', '!four:server']);
  });

  test(
    'explicit room order syncs category order without changing fallback',
    () {
      const state = SpaceRoomCategoryState(
        categories: [
          SpaceRoomCategoryDefinition(
            id: 'alpha',
            name: 'Alpha',
            roomIds: ['!two:server', '!one:server', '!three:server'],
            roomOrderIds: ['!two:server', '!one:server'],
          ),
        ],
      );

      final groups = buildSpaceRoomCategoryGroups<String>(
        state: state,
        rooms: ['!one:server', '!three:server', '!two:server', '!four:server'],
        roomId: (roomId) => roomId,
      );

      expect(groups[0].rooms, ['!two:server', '!one:server', '!three:server']);
      expect(groups[1].isUncategorized, isTrue);
      expect(groups[1].rooms, ['!four:server']);
    },
  );

  test('explicit uncategorized room order syncs uncategorized group', () {
    const state = SpaceRoomCategoryState(
      categories: [
        SpaceRoomCategoryDefinition(
          id: 'alpha',
          name: 'Alpha',
          roomIds: ['!one:server'],
        ),
      ],
      uncategorizedRoomOrderIds: ['!three:server', '!two:server'],
    );

    final groups = buildSpaceRoomCategoryGroups<String>(
      state: state,
      rooms: ['!one:server', '!two:server', '!three:server'],
      roomId: (roomId) => roomId,
    );

    expect(groups[0].rooms, ['!one:server']);
    expect(groups[1].isUncategorized, isTrue);
    expect(groups[1].rooms, ['!three:server', '!two:server']);
  });

  test('normalizes stale and duplicate room ids', () {
    const state = SpaceRoomCategoryState(
      categories: [
        SpaceRoomCategoryDefinition(
          id: 'alpha',
          name: 'Alpha',
          roomIds: ['!two:server', '!two:server', '!missing:server'],
          roomOrderIds: ['!missing:server', '!two:server', '!two:server'],
        ),
        SpaceRoomCategoryDefinition(
          id: 'beta',
          name: 'Beta',
          roomIds: ['!one:server', '!two:server'],
          roomOrderIds: ['!one:server', '!two:server'],
        ),
      ],
      uncategorizedRoomOrderIds: ['!ghost:server', '!three:server'],
    );

    final normalized = state.normalizedForRoomIds([
      '!one:server',
      '!two:server',
      '!three:server',
    ]);

    expect(normalized.categories[0].roomIds, ['!two:server']);
    expect(normalized.categories[0].roomOrderIds, ['!two:server']);
    expect(normalized.categories[1].roomIds, ['!one:server']);
    expect(normalized.categories[1].roomOrderIds, ['!one:server']);
    expect(normalized.uncategorizedRoomOrderIds, ['!three:server']);
  });
}
