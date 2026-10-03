import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:intergalactic/client/favorite_room_categories.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/client/space.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const String matrixSpaceRoomCategoriesEventType =
    'chat.intergalactic.space.categories';

final spaceRoomCategoryStore = SpaceRoomCategoryStore();

String normalizeSpaceRoomCategoryName(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed.isEmpty ? 'New Category' : trimmed;
}

/// Whether this account may edit the space's category state event.
///
/// `canChangeStateEvent` is the whole answer. It reads the space's own
/// `m.room.power_levels`, including an explicit entry for this event type in
/// the `events` map, so a space that deliberately grants categories at PL 50
/// is honoured.
///
/// It used to ALSO require power level 100. That extra clause could only ever
/// disagree with the room by refusing something the room had allowed: the room
/// said yes and the client said no, with no way to tell the user why. Matrix
/// has no notion of "space admin" beyond the power levels the space itself
/// declares, so there was nothing for the hardcoded number to be right about.
bool canManageSpaceRoomCategories(Space space) {
  if (space case MatrixSpace matrixSpace) {
    return matrixSpace.matrixRoom.canChangeStateEvent(
      matrixSpaceRoomCategoriesEventType,
    );
  }

  return space.permissions.canEditChildren;
}

/// The scope of the DEVICE-LOCAL category store.
///
/// It exists so a Matrix space's id cannot be handed to the local-only path.
/// A Matrix space keeps its categories in a room state event on the space,
/// shared with every member; the local store serves spaces that have no server
/// to write to - the favourites pseudo-space, and any future non-Matrix space.
///
/// Before this type both paths took a bare `String spaceLocalId`, so a Matrix
/// space could be written to the local store by passing the wrong id. Nothing
/// read it back - `loadForSpace` goes to room state for a Matrix space - so the
/// copy would sit there, stale, diverging silently from the shared truth. That
/// is limb 2 of the space-categories audit, and a type is a better answer to it
/// than a guard, because it removes the call rather than rejecting it.
extension type const LocalSpaceCategoryScope._(String localId) {
  /// The favourites pseudo-space, which has no Matrix room behind it.
  static const favorites = LocalSpaceCategoryScope._(
    favoriteRoomCategoriesLocalId,
  );

  /// For a space with no server-side home for its categories.
  ///
  /// Throws for a [MatrixSpace]: that is a caller reaching for the wrong store,
  /// not a case to fall back on.
  factory LocalSpaceCategoryScope.forSpace(Space space) {
    if (space is MatrixSpace) {
      throw ArgumentError.value(
        space.identifier,
        'space',
        'A Matrix space keeps its categories in room state. Use the ForSpace '
            'methods, which write the shared event.',
      );
    }
    return LocalSpaceCategoryScope._(space.localId);
  }

  /// For tests that exercise the local store's own behaviour - per-client
  /// isolation, ordering - with synthetic ids rather than a Space.
  @visibleForTesting
  factory LocalSpaceCategoryScope.forTesting(String localId) =>
      LocalSpaceCategoryScope._(localId);

  /// For account-scoped local state that has no Space object behind it.
  factory LocalSpaceCategoryScope.forClient(String localId) =>
      LocalSpaceCategoryScope._(localId);
}

class SpaceRoomCategoryDefinition {
  const SpaceRoomCategoryDefinition({
    required this.id,
    required this.name,
    this.roomIds = const [],
    this.roomOrderIds = const [],
    this.collapsed = false,
  });

  factory SpaceRoomCategoryDefinition.fromJson(Map<String, Object?> json) {
    return SpaceRoomCategoryDefinition(
      id: json['id'] is String ? json['id'] as String : const Uuid().v4(),
      name: normalizeSpaceRoomCategoryName(
        json['name'] is String ? json['name'] as String : '',
      ),
      roomIds: json['room_ids'] is List
          ? (json['room_ids'] as List).whereType<String>().toList()
          : const [],
      roomOrderIds: json['room_order_ids'] is List
          ? (json['room_order_ids'] as List).whereType<String>().toList()
          : const [],
      collapsed: json['collapsed'] == true,
    );
  }

  final String id;
  final String name;
  final List<String> roomIds;
  final List<String> roomOrderIds;
  final bool collapsed;

  SpaceRoomCategoryDefinition copyWith({
    String? id,
    String? name,
    List<String>? roomIds,
    List<String>? roomOrderIds,
    bool? collapsed,
  }) {
    return SpaceRoomCategoryDefinition(
      id: id ?? this.id,
      name: name == null ? this.name : normalizeSpaceRoomCategoryName(name),
      roomIds: roomIds ?? this.roomIds,
      roomOrderIds: roomOrderIds ?? this.roomOrderIds,
      collapsed: collapsed ?? this.collapsed,
    );
  }

  Map<String, Object?> toJson({bool includeLocalState = true}) {
    final json = <String, Object?>{'id': id, 'name': name, 'room_ids': roomIds};
    if (roomOrderIds.isNotEmpty) {
      json['room_order_ids'] = roomOrderIds;
    }
    if (includeLocalState) {
      json['collapsed'] = collapsed;
    }
    return json;
  }
}

class SpaceRoomCategoryState {
  const SpaceRoomCategoryState({
    this.categories = const [],
    this.uncategorizedCollapsed = false,
    this.uncategorizedRoomOrderIds = const [],
  });

  factory SpaceRoomCategoryState.fromJson(Map<String, Object?> json) {
    return SpaceRoomCategoryState(
      categories: json['categories'] is List
          ? (json['categories'] as List)
                .whereType<Map>()
                .map(
                  (category) => SpaceRoomCategoryDefinition.fromJson(
                    Map<String, Object?>.from(category),
                  ),
                )
                .toList()
          : const [],
      uncategorizedCollapsed: json['uncategorized_collapsed'] == true,
      uncategorizedRoomOrderIds: json['uncategorized_room_order_ids'] is List
          ? (json['uncategorized_room_order_ids'] as List)
                .whereType<String>()
                .toList()
          : const [],
    );
  }

  factory SpaceRoomCategoryState.fromMatrixStateContent(
    Map<String, Object?> json,
  ) {
    final state = SpaceRoomCategoryState.fromJson(json);
    return state.copyWith(
      categories: [
        for (final category in state.categories)
          category.copyWith(collapsed: false),
      ],
      uncategorizedCollapsed: false,
    );
  }

  static const empty = SpaceRoomCategoryState();

  final List<SpaceRoomCategoryDefinition> categories;
  final bool uncategorizedCollapsed;
  final List<String> uncategorizedRoomOrderIds;

  bool get hasCategories => categories.isNotEmpty;
  bool get hasPersistedState =>
      categories.isNotEmpty ||
      uncategorizedCollapsed ||
      uncategorizedRoomOrderIds.isNotEmpty;

  SpaceRoomCategoryState copyWith({
    List<SpaceRoomCategoryDefinition>? categories,
    bool? uncategorizedCollapsed,
    List<String>? uncategorizedRoomOrderIds,
  }) {
    return SpaceRoomCategoryState(
      categories: categories ?? this.categories,
      uncategorizedCollapsed:
          uncategorizedCollapsed ?? this.uncategorizedCollapsed,
      uncategorizedRoomOrderIds:
          uncategorizedRoomOrderIds ?? this.uncategorizedRoomOrderIds,
    );
  }

  SpaceRoomCategoryState normalizedForRoomIds(Iterable<String> roomIds) {
    final activeRoomIds = roomIds.toSet();
    final usedRoomIds = <String>{};
    final usedCategoryIds = <String>{};
    final normalizedCategories = <SpaceRoomCategoryDefinition>[];

    for (final category in categories) {
      if (!usedCategoryIds.add(category.id)) {
        continue;
      }

      final normalizedRoomIds = <String>[];
      for (final roomId in category.roomIds) {
        if (!activeRoomIds.contains(roomId) || !usedRoomIds.add(roomId)) {
          continue;
        }

        normalizedRoomIds.add(roomId);
      }
      final normalizedRoomIdSet = normalizedRoomIds.toSet();
      final normalizedRoomOrderIds = <String>[];
      for (final roomId in category.roomOrderIds) {
        if (!normalizedRoomIdSet.contains(roomId) ||
            normalizedRoomOrderIds.contains(roomId)) {
          continue;
        }

        normalizedRoomOrderIds.add(roomId);
      }

      normalizedCategories.add(
        category.copyWith(
          roomIds: normalizedRoomIds,
          roomOrderIds: normalizedRoomOrderIds,
        ),
      );
    }

    final normalizedUncategorizedOrderIds = <String>[];
    for (final roomId in uncategorizedRoomOrderIds) {
      if (!activeRoomIds.contains(roomId) ||
          usedRoomIds.contains(roomId) ||
          normalizedUncategorizedOrderIds.contains(roomId)) {
        continue;
      }

      normalizedUncategorizedOrderIds.add(roomId);
    }

    return copyWith(
      categories: normalizedCategories,
      uncategorizedRoomOrderIds: normalizedUncategorizedOrderIds,
    );
  }

  SpaceRoomCategoryState withLocalViewState(
    SpaceRoomCategoryState localViewState,
  ) {
    final collapsedByCategoryId = {
      for (final category in localViewState.categories)
        category.id: category.collapsed,
    };

    return copyWith(
      categories: [
        for (final category in categories)
          category.copyWith(
            collapsed: collapsedByCategoryId[category.id] ?? false,
          ),
      ],
      uncategorizedCollapsed: localViewState.uncategorizedCollapsed,
    );
  }

  SpaceRoomCategoryState withExplicitRoomOrder(
    String groupId,
    List<String> orderedRoomIds,
  ) {
    final uniqueOrderedRoomIds = <String>[];
    for (final roomId in orderedRoomIds) {
      if (!uniqueOrderedRoomIds.contains(roomId)) {
        uniqueOrderedRoomIds.add(roomId);
      }
    }

    if (groupId == SpaceRoomCategoryStore.uncategorizedGroupId) {
      return copyWith(uncategorizedRoomOrderIds: uniqueOrderedRoomIds);
    }

    return copyWith(
      categories: [
        for (final category in categories)
          if (category.id == groupId)
            category.copyWith(
              roomOrderIds: [
                for (final roomId in uniqueOrderedRoomIds)
                  if (category.roomIds.contains(roomId)) roomId,
              ],
            )
          else
            category,
      ],
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'categories': categories.map((category) => category.toJson()).toList(),
      'uncategorized_collapsed': uncategorizedCollapsed,
    };
    if (uncategorizedRoomOrderIds.isNotEmpty) {
      json['uncategorized_room_order_ids'] = uncategorizedRoomOrderIds;
    }
    return json;
  }

  Map<String, dynamic> toMatrixStateContent() {
    final content = <String, dynamic>{
      'version': 1,
      'categories': [
        for (final category in categories)
          category.toJson(includeLocalState: false),
      ],
    };
    if (uncategorizedRoomOrderIds.isNotEmpty) {
      content['uncategorized_room_order_ids'] = uncategorizedRoomOrderIds;
    }
    return content;
  }
}

class SpaceRoomCategoryGroup<T> {
  const SpaceRoomCategoryGroup({
    required this.id,
    required this.name,
    required this.rooms,
    required this.collapsed,
    this.isUncategorized = false,
  });

  final String id;
  final String name;
  final List<T> rooms;
  final bool collapsed;
  final bool isUncategorized;
}

List<SpaceRoomCategoryGroup<T>> buildSpaceRoomCategoryGroups<T>({
  required SpaceRoomCategoryState state,
  required Iterable<T> rooms,
  required String Function(T room) roomId,
  String uncategorizedLabel = 'Uncategorized',
}) {
  final activeRoomIds = <String>{};
  for (final room in rooms) {
    activeRoomIds.add(roomId(room));
  }

  final categoryIdByRoomId = <String, String>{};
  for (final category in state.categories) {
    for (final id in category.roomIds) {
      if (!activeRoomIds.contains(id)) {
        continue;
      }

      categoryIdByRoomId.putIfAbsent(id, () => category.id);
    }
  }

  final roomsByCategoryId = <String, List<T>>{
    for (final category in state.categories) category.id: <T>[],
  };
  final uncategorizedRooms = <T>[];
  final displayedRoomIds = <String>{};

  for (final room in rooms) {
    final id = roomId(room);
    if (!displayedRoomIds.add(id)) {
      continue;
    }

    final categoryId = categoryIdByRoomId[id];
    if (categoryId == null) {
      uncategorizedRooms.add(room);
      continue;
    }

    roomsByCategoryId[categoryId]?.add(room);
  }

  final groups = <SpaceRoomCategoryGroup<T>>[];

  for (final category in state.categories) {
    final categoryRooms = roomsByCategoryId[category.id] ?? <T>[];
    groups.add(
      SpaceRoomCategoryGroup<T>(
        id: category.id,
        name: category.name,
        rooms: _applyExplicitRoomOrder<T>(
          categoryRooms,
          category.roomOrderIds,
          roomId,
        ),
        collapsed: category.collapsed,
      ),
    );
  }

  if (uncategorizedRooms.isNotEmpty) {
    groups.add(
      SpaceRoomCategoryGroup<T>(
        id: SpaceRoomCategoryStore.uncategorizedGroupId,
        name: uncategorizedLabel,
        rooms: _applyExplicitRoomOrder<T>(
          uncategorizedRooms,
          state.uncategorizedRoomOrderIds,
          roomId,
        ),
        collapsed: state.uncategorizedCollapsed,
        isUncategorized: true,
      ),
    );
  }

  return groups;
}

List<T> _applyExplicitRoomOrder<T>(
  List<T> rooms,
  List<String> explicitOrder,
  String Function(T room) roomId,
) {
  if (rooms.length < 2 || explicitOrder.isEmpty) {
    return rooms;
  }

  final remainingById = <String, T>{
    for (final room in rooms) roomId(room): room,
  };
  final ordered = <T>[];
  for (final id in explicitOrder) {
    final room = remainingById.remove(id);
    if (room != null) {
      ordered.add(room);
    }
  }

  for (final room in rooms) {
    final id = roomId(room);
    if (remainingById.remove(id) != null) {
      ordered.add(room);
    }
  }

  return ordered;
}

class SpaceRoomCategoryChanged {
  const SpaceRoomCategoryChanged({
    required this.spaceLocalId,
    required this.state,
  });

  final String spaceLocalId;
  final SpaceRoomCategoryState state;
}

class SpaceRoomCategoryStore {
  SpaceRoomCategoryStore({
    SharedPreferences? preferences,
    String Function()? idFactory,
  }) : _preferences = preferences,
       _idFactory = idFactory ?? const Uuid().v4;

  static const uncategorizedGroupId = '__uncategorized__';
  static const _keyPrefix = 'space_room_categories.v1.';
  static const _viewStateKeyPrefix = 'space_room_categories.view_state.v1.';

  final String Function() _idFactory;
  SharedPreferences? _preferences;
  final StreamController<SpaceRoomCategoryChanged> _onChanged =
      StreamController.broadcast();

  Stream<SpaceRoomCategoryChanged> get onChanged => _onChanged.stream;

  Future<SpaceRoomCategoryState> loadForSpace(Space space) async {
    if (space case MatrixSpace matrixSpace) {
      final sharedState = _loadMatrixState(matrixSpace);
      final localViewState = await _loadLocalViewState(space.localId);
      return sharedState.withLocalViewState(localViewState);
    }

    return load(LocalSpaceCategoryScope.forSpace(space));
  }

  Future<SpaceRoomCategoryState> load(LocalSpaceCategoryScope scope) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_storageKey(scope.localId));
    if (raw == null || raw.isEmpty) {
      return SpaceRoomCategoryState.empty;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return SpaceRoomCategoryState.empty;
      }

      return SpaceRoomCategoryState.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } catch (_) {
      return SpaceRoomCategoryState.empty;
    }
  }

  Future<SpaceRoomCategoryDefinition> createCategory(
    LocalSpaceCategoryScope scope,
    String name,
  ) async {
    final state = await load(scope);
    final category = SpaceRoomCategoryDefinition(
      id: _idFactory(),
      name: normalizeSpaceRoomCategoryName(name),
    );

    await save(
      scope,
      state.copyWith(categories: [...state.categories, category]),
    );
    return category;
  }

  Future<SpaceRoomCategoryDefinition> createCategoryForSpace(
    Space space,
    String name,
  ) async {
    final state = await loadForSpace(space);
    final category = SpaceRoomCategoryDefinition(
      id: _idFactory(),
      name: normalizeSpaceRoomCategoryName(name),
    );

    await saveForSpace(
      space,
      state.copyWith(categories: [...state.categories, category]),
    );
    return category;
  }

  Future<void> renameCategory(
    LocalSpaceCategoryScope scope,
    String categoryId,
    String name,
  ) async {
    final state = await load(scope);
    await save(
      scope,
      state.copyWith(
        categories: [
          for (final category in state.categories)
            if (category.id == categoryId)
              category.copyWith(name: name)
            else
              category,
        ],
      ),
    );
  }

  Future<void> renameCategoryForSpace(
    Space space,
    String categoryId,
    String name,
  ) async {
    final state = await loadForSpace(space);
    await saveForSpace(
      space,
      state.copyWith(
        categories: [
          for (final category in state.categories)
            if (category.id == categoryId)
              category.copyWith(name: name)
            else
              category,
        ],
      ),
    );
  }

  Future<void> deleteCategory(
    LocalSpaceCategoryScope scope,
    String categoryId,
  ) async {
    final state = await load(scope);
    await save(
      scope,
      state.copyWith(
        categories: [
          for (final category in state.categories)
            if (category.id != categoryId) category,
        ],
      ),
    );
  }

  Future<void> deleteCategoryForSpace(Space space, String categoryId) async {
    final state = await loadForSpace(space);
    await saveForSpace(
      space,
      state.copyWith(
        categories: [
          for (final category in state.categories)
            if (category.id != categoryId) category,
        ],
      ),
    );
  }

  Future<void> moveCategory(
    LocalSpaceCategoryScope scope,
    String categoryId,
    int newIndex,
  ) async {
    final state = await load(scope);
    final categories = List<SpaceRoomCategoryDefinition>.from(state.categories);
    final oldIndex = categories.indexWhere(
      (category) => category.id == categoryId,
    );
    if (oldIndex < 0 || categories.length < 2) {
      return;
    }

    final category = categories.removeAt(oldIndex);
    final targetIndex = newIndex.clamp(0, categories.length).toInt();
    categories.insert(targetIndex, category);
    await save(scope, state.copyWith(categories: categories));
  }

  Future<void> moveCategoryForSpace(
    Space space,
    String categoryId,
    int newIndex,
  ) async {
    final state = await loadForSpace(space);
    final categories = List<SpaceRoomCategoryDefinition>.from(state.categories);
    final oldIndex = categories.indexWhere(
      (category) => category.id == categoryId,
    );
    if (oldIndex < 0 || categories.length < 2) {
      return;
    }

    final category = categories.removeAt(oldIndex);
    final targetIndex = newIndex.clamp(0, categories.length).toInt();
    categories.insert(targetIndex, category);
    await saveForSpace(space, state.copyWith(categories: categories));
  }

  Future<void> setCategoryCollapsed(
    LocalSpaceCategoryScope scope,
    String categoryId,
    bool collapsed,
  ) async {
    final state = await load(scope);
    await save(
      scope,
      state.copyWith(
        categories: [
          for (final category in state.categories)
            if (category.id == categoryId)
              category.copyWith(collapsed: collapsed)
            else
              category,
        ],
      ),
    );
  }

  Future<void> setCategoryCollapsedForSpace(
    Space space,
    String categoryId,
    bool collapsed,
  ) async {
    if (space is! MatrixSpace) {
      await setCategoryCollapsed(
        LocalSpaceCategoryScope.forSpace(space),
        categoryId,
        collapsed,
      );
      return;
    }

    final state = await loadForSpace(space);
    final updated = state.copyWith(
      categories: [
        for (final category in state.categories)
          if (category.id == categoryId)
            category.copyWith(collapsed: collapsed)
          else
            category,
      ],
    );
    await _saveLocalViewState(space.localId, updated);
    _emitChanged(space.localId, updated);
  }

  Future<void> setUncategorizedCollapsed(
    LocalSpaceCategoryScope scope,
    bool collapsed,
  ) async {
    final state = await load(scope);
    await save(scope, state.copyWith(uncategorizedCollapsed: collapsed));
  }

  Future<void> setUncategorizedCollapsedForSpace(
    Space space,
    bool collapsed,
  ) async {
    if (space is! MatrixSpace) {
      await setUncategorizedCollapsed(
        LocalSpaceCategoryScope.forSpace(space),
        collapsed,
      );
      return;
    }

    final state = await loadForSpace(space);
    final updated = state.copyWith(uncategorizedCollapsed: collapsed);
    await _saveLocalViewState(space.localId, updated);
    _emitChanged(space.localId, updated);
  }

  Future<void> assignRoomToCategory(
    LocalSpaceCategoryScope scope,
    String roomId,
    String categoryId,
  ) async {
    final state = await load(scope);
    await save(
      scope,
      state.copyWith(
        categories: [
          for (final category in state.categories)
            if (category.id == categoryId)
              category.copyWith(
                roomIds: [
                  ...category.roomIds.where((id) => id != roomId),
                  roomId,
                ],
                roomOrderIds: category.roomOrderIds.isEmpty
                    ? const []
                    : [
                        ...category.roomOrderIds.where((id) => id != roomId),
                        roomId,
                      ],
              )
            else
              category.copyWith(
                roomIds: [
                  for (final id in category.roomIds)
                    if (id != roomId) id,
                ],
                roomOrderIds: [
                  for (final id in category.roomOrderIds)
                    if (id != roomId) id,
                ],
              ),
        ],
      ),
    );
  }

  Future<void> assignRoomToCategoryForSpace(
    Space space,
    String roomId,
    String categoryId,
  ) async {
    final state = await loadForSpace(space);
    await saveForSpace(
      space,
      state.copyWith(
        categories: [
          for (final category in state.categories)
            if (category.id == categoryId)
              category.copyWith(
                roomIds: [
                  ...category.roomIds.where((id) => id != roomId),
                  roomId,
                ],
                roomOrderIds: category.roomOrderIds.isEmpty
                    ? const []
                    : [
                        ...category.roomOrderIds.where((id) => id != roomId),
                        roomId,
                      ],
              )
            else
              category.copyWith(
                roomIds: [
                  for (final id in category.roomIds)
                    if (id != roomId) id,
                ],
                roomOrderIds: [
                  for (final id in category.roomOrderIds)
                    if (id != roomId) id,
                ],
              ),
        ],
      ),
    );
  }

  Future<void> unassignRoom(
    LocalSpaceCategoryScope scope,
    String roomId,
  ) async {
    final state = await load(scope);
    await save(
      scope,
      state.copyWith(
        categories: [
          for (final category in state.categories)
            category.copyWith(
              roomIds: [
                for (final id in category.roomIds)
                  if (id != roomId) id,
              ],
              roomOrderIds: [
                for (final id in category.roomOrderIds)
                  if (id != roomId) id,
              ],
            ),
        ],
      ),
    );
  }

  Future<void> unassignRoomForSpace(Space space, String roomId) async {
    final state = await loadForSpace(space);
    await saveForSpace(
      space,
      state.copyWith(
        categories: [
          for (final category in state.categories)
            category.copyWith(
              roomIds: [
                for (final id in category.roomIds)
                  if (id != roomId) id,
              ],
              roomOrderIds: [
                for (final id in category.roomOrderIds)
                  if (id != roomId) id,
              ],
            ),
        ],
      ),
    );
  }

  Future<void> save(
    LocalSpaceCategoryScope scope,
    SpaceRoomCategoryState state,
  ) async {
    final prefs = await _prefs();
    if (!state.hasPersistedState) {
      await prefs.remove(_storageKey(scope.localId));
    } else {
      await prefs.setString(
        _storageKey(scope.localId),
        jsonEncode(state.toJson()),
      );
    }

    _onChanged.add(
      SpaceRoomCategoryChanged(spaceLocalId: scope.localId, state: state),
    );
  }

  Future<void> saveForSpace(Space space, SpaceRoomCategoryState state) async {
    if (space case MatrixSpace matrixSpace) {
      if (!canManageSpaceRoomCategories(space)) {
        throw Exception('Only space admins can manage room categories.');
      }

      final sharedState = state.copyWith(
        categories: [
          for (final category in state.categories)
            category.copyWith(collapsed: false),
        ],
        uncategorizedCollapsed: false,
      );
      final eventId = await matrixSpace.matrixRoom.client.setRoomStateWithKey(
        matrixSpace.identifier,
        matrixSpaceRoomCategoriesEventType,
        '',
        sharedState.toMatrixStateContent(),
      );
      final event = await matrixSpace.matrixRoom.getEventById(eventId);
      final states = matrixSpace.matrixRoom.states.putIfAbsent(
        matrixSpaceRoomCategoriesEventType,
        () => <String, matrix.StrippedStateEvent>{},
      );
      if (event != null) {
        states[''] = event;
      }

      final mergedState = sharedState.withLocalViewState(
        await _loadLocalViewState(space.localId),
      );
      _emitChanged(space.localId, mergedState);
      matrixSpace.notifyUpdate();
      return;
    }

    await save(LocalSpaceCategoryScope.forSpace(space), state);
  }

  Future<void> dispose() async {
    await _onChanged.close();
  }

  Future<SharedPreferences> _prefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  SpaceRoomCategoryState _loadMatrixState(MatrixSpace space) {
    final event = space.matrixRoom.getState(matrixSpaceRoomCategoriesEventType);
    final content = event?.content;
    if (content == null) {
      return SpaceRoomCategoryState.empty;
    }

    return SpaceRoomCategoryState.fromMatrixStateContent(
      Map<String, Object?>.from(content),
    );
  }

  Future<SpaceRoomCategoryState> _loadLocalViewState(
    String spaceLocalId,
  ) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_viewStateStorageKey(spaceLocalId));
    if (raw == null || raw.isEmpty) {
      return SpaceRoomCategoryState.empty;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return SpaceRoomCategoryState.empty;
      }

      return SpaceRoomCategoryState.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } catch (_) {
      return SpaceRoomCategoryState.empty;
    }
  }

  Future<void> _saveLocalViewState(
    String spaceLocalId,
    SpaceRoomCategoryState state,
  ) async {
    final prefs = await _prefs();
    final localState = SpaceRoomCategoryState(
      categories: [
        for (final category in state.categories)
          if (category.collapsed)
            SpaceRoomCategoryDefinition(
              id: category.id,
              name: category.name,
              collapsed: true,
            ),
      ],
      uncategorizedCollapsed: state.uncategorizedCollapsed,
    );

    if (!localState.hasPersistedState) {
      await prefs.remove(_viewStateStorageKey(spaceLocalId));
      return;
    }

    await prefs.setString(
      _viewStateStorageKey(spaceLocalId),
      jsonEncode(localState.toJson()),
    );
  }

  void _emitChanged(String spaceLocalId, SpaceRoomCategoryState state) {
    _onChanged.add(
      SpaceRoomCategoryChanged(spaceLocalId: spaceLocalId, state: state),
    );
  }

  String _storageKey(String spaceLocalId) {
    return '$_keyPrefix${base64Url.encode(utf8.encode(spaceLocalId))}';
  }

  String _viewStateStorageKey(String spaceLocalId) {
    return '$_viewStateKeyPrefix${base64Url.encode(utf8.encode(spaceLocalId))}';
  }
}
