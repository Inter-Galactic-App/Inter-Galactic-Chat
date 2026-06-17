import 'package:flutter_test/flutter_test.dart';
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
      'client-a:!space:server',
      '  Raid   Rooms  ',
    );
    await store.assignRoomToCategory(
      'client-a:!space:server',
      '!general:server',
      category.id,
    );

    final state = await store.load('client-a:!space:server');
    final otherState = await store.load('client-b:!space:server');

    expect(state.categories, hasLength(1));
    expect(state.categories.single.name, 'Raid Rooms');
    expect(state.categories.single.roomIds, ['!general:server']);
    expect(otherState.categories, isEmpty);
    expect(
      changes.map((change) => change.spaceLocalId).toSet(),
      {'client-a:!space:server'},
    );
  });

  test('Matrix state content excludes local collapse state', () {
    const state = SpaceRoomCategoryState(
      categories: [
        SpaceRoomCategoryDefinition(
          id: 'alpha',
          name: 'Alpha',
          roomIds: ['!one:server'],
          collapsed: true,
        ),
      ],
      uncategorizedCollapsed: true,
    );

    expect(
      state.toMatrixStateContent(),
      {
        'version': 1,
        'categories': [
          {
            'id': 'alpha',
            'name': 'Alpha',
            'room_ids': ['!one:server'],
          },
        ],
      },
    );

    final parsed = SpaceRoomCategoryState.fromMatrixStateContent({
      'categories': [
        {
          'id': 'alpha',
          'name': 'Alpha',
          'room_ids': ['!one:server'],
          'collapsed': true,
        },
      ],
      'uncategorized_collapsed': true,
    });

    expect(parsed.categories.single.collapsed, isFalse);
    expect(parsed.uncategorizedCollapsed, isFalse);
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
        SpaceRoomCategoryDefinition(
          id: 'beta',
          name: 'Beta',
          collapsed: true,
        ),
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

    final alpha = await store.createCategory('client:!space', 'Alpha');
    final beta = await store.createCategory('client:!space', 'Beta');

    await store.assignRoomToCategory(
      'client:!space',
      '!room:server',
      alpha.id,
    );
    await store.assignRoomToCategory(
      'client:!space',
      '!room:server',
      beta.id,
    );

    final state = await store.load('client:!space');

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
      rooms: [
        '!one:server',
        '!three:server',
        '!two:server',
        '!four:server',
      ],
      roomId: (roomId) => roomId,
    );

    expect(groups[0].rooms, ['!one:server', '!two:server']);
    expect(groups[1].rooms, ['!three:server', '!four:server']);
  });

  test('normalizes stale and duplicate room ids', () {
    const state = SpaceRoomCategoryState(
      categories: [
        SpaceRoomCategoryDefinition(
          id: 'alpha',
          name: 'Alpha',
          roomIds: ['!two:server', '!two:server', '!missing:server'],
        ),
        SpaceRoomCategoryDefinition(
          id: 'beta',
          name: 'Beta',
          roomIds: ['!one:server', '!two:server'],
        ),
      ],
    );

    final normalized = state.normalizedForRoomIds([
      '!one:server',
      '!two:server',
    ]);

    expect(normalized.categories[0].roomIds, ['!two:server']);
    expect(normalized.categories[1].roomIds, ['!one:server']);
  });
}
