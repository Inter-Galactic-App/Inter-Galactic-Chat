import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/favorite_room_categories.dart';
import 'package:intergalactic/client/space_room_categories.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/category_settings_header.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class FavoritesCategoriesSettingsPage extends StatefulWidget {
  const FavoritesCategoriesSettingsPage({
    required this.clientManager,
    super.key,
  });

  final ClientManager clientManager;

  @override
  State<FavoritesCategoriesSettingsPage> createState() =>
      _FavoritesCategoriesSettingsPageState();
}

class _FavoritesCategoriesSettingsPageState
    extends State<FavoritesCategoriesSettingsPage> {
  SpaceRoomCategoryState _state = SpaceRoomCategoryState.empty;
  late final List<StreamSubscription> _subscriptions;
  bool _loaded = false;
  bool _saving = false;

  List<Room> get _favoriteRooms {
    final favoriteIds = preferences.getFavoriteRoomIds();
    final order = <String, int>{
      for (var i = 0; i < favoriteIds.length; i++) favoriteIds[i]: i,
    };

    final rooms = widget.clientManager.rooms.where((room) {
      return preferences.isRoomFavorite(
        room.favoriteStorageId,
        legacyRoomId: room.localId,
      );
    }).toList();

    int sortOrder(Room room) {
      final stableOrder = order[room.favoriteStorageId];
      final legacyOrder = order[room.localId];
      if (stableOrder == null) return legacyOrder ?? favoriteIds.length;
      if (legacyOrder == null) return stableOrder;
      return stableOrder < legacyOrder ? stableOrder : legacyOrder;
    }

    rooms.sort((a, b) => sortOrder(a).compareTo(sortOrder(b)));
    return rooms;
  }

  @override
  void initState() {
    super.initState();
    _subscriptions = [
      spaceRoomCategoryStore.onChanged
          .where((event) => event.spaceLocalId == favoriteRoomCategoriesLocalId)
          .listen(_onCategoryStateChanged),
      preferences.onSettingChanged.listen((_) => _loadState()),
      widget.clientManager.onRoomAdded.listen((_) => _loadState()),
      widget.clientManager.onRoomRemoved.listen((_) => _loadState()),
      widget.clientManager.onClientUpdated.stream.listen((_) => _loadState()),
    ];
    _loadState();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<void> _loadState() async {
    final favoriteRoomIds = _favoriteRooms
        .map((room) => room.favoriteStorageId)
        .toList(growable: false);
    final state = await loadFavoriteRoomCategoryState(
      favoriteRoomIds: favoriteRoomIds,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _state = state.normalizedForRoomIds(
        _favoriteRooms.map((room) => room.favoriteStorageId),
      );
      _loaded = true;
    });
  }

  void _onCategoryStateChanged(SpaceRoomCategoryChanged event) {
    if (!mounted) {
      return;
    }

    setState(() {
      _state = event.state.normalizedForRoomIds(
        _favoriteRooms.map((room) => room.favoriteStorageId),
      );
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _favoriteRooms;
    final categories = _state.categories;
    final unassignedRooms = rooms
        .where((room) => _categoryForRoom(room.favoriteStorageId) == null)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Favorite Room Categories',
          children: [
            SettingsControlRow(
              title: 'Local favorite groups',
              description:
                  'Organize favorite rooms from every signed-in account and homeserver in one local Favorites view. These categories do not change Matrix spaces or room membership.',
              trailing: ElevatedButton.icon(
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add category'),
                onPressed: _saving ? null : _createCategory,
              ),
              child: !_loaded
                  ? const SettingsStatePanel(
                      icon: Icons.sync,
                      title: 'Loading favorite categories',
                      description:
                          'Checking your local Favorites organization.',
                      padding: EdgeInsets.zero,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (rooms.isEmpty)
                          SettingsStatePanel(
                            icon: Icons.star_border_rounded,
                            title: 'No favorite rooms yet',
                            description:
                                'Star rooms from room lists or room menus before creating categories.',
                            padding: EdgeInsets.zero,
                          )
                        else if (categories.isEmpty)
                          SettingsStatePanel(
                            icon: Icons.create_new_folder_outlined,
                            title: 'No categories yet',
                            description:
                                'Add a category to group favorite rooms across your signed-in accounts.',
                            padding: EdgeInsets.zero,
                            action: ElevatedButton.icon(
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                              ),
                              label: const Text('Add category'),
                              onPressed: _saving ? null : _createCategory,
                            ),
                          )
                        else ...[
                          tiamat.Text.labelLow(
                            unassignedRooms.isEmpty
                                ? 'All favorite rooms are assigned to a category.'
                                : '${unassignedRooms.length} favorite room${unassignedRooms.length == 1 ? '' : 's'} will stay in Uncategorized.',
                          ),
                          const SizedBox(height: 12),
                          for (int i = 0; i < categories.length; i++)
                            _categoryCard(categories[i], i, categories.length),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _categoryCard(
    SpaceRoomCategoryDefinition category,
    int index,
    int categoryCount,
  ) {
    final theme = Theme.of(context);
    final rooms = _favoriteRooms;
    final assignedCurrentRooms = rooms
        .where((room) => category.roomIds.contains(room.favoriteStorageId))
        .length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CategorySettingsHeader(
                name: category.name,
                roomCountLabel:
                    '$assignedCurrentRooms room${assignedCurrentRooms == 1 ? '' : 's'}',
                collapsed: category.collapsed,
                actions: [
                  IconButton(
                    tooltip: category.collapsed
                        ? 'Expand locally in Favorites'
                        : 'Collapse locally in Favorites',
                    icon: Icon(
                      category.collapsed
                          ? Icons.unfold_more
                          : Icons.unfold_less,
                    ),
                    onPressed: _saving
                        ? null
                        : () => _setCategoryCollapsed(
                            category,
                            !category.collapsed,
                          ),
                  ),
                  IconButton(
                    tooltip: 'Move up',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _saving || index == 0
                        ? null
                        : () => _moveCategory(category, index - 1),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: _saving || index == categoryCount - 1
                        ? null
                        : () => _moveCategory(category, index + 1),
                  ),
                  IconButton(
                    tooltip: 'Rename category',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _saving ? null : () => _renameCategory(category),
                  ),
                  IconButton(
                    tooltip: 'Delete category',
                    icon: const Icon(Icons.delete_outline),
                    color: theme.colorScheme.error,
                    onPressed: _saving ? null : () => _deleteCategory(category),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final room in rooms)
                _roomAssignmentTile(category: category, room: room),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roomAssignmentTile({
    required SpaceRoomCategoryDefinition category,
    required Room room,
  }) {
    final assignedCategory = _categoryForRoom(room.favoriteStorageId);
    final assignedHere = assignedCategory?.id == category.id;
    final assignedElsewhere = assignedCategory != null && !assignedHere;

    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        room.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        assignedElsewhere
            ? 'Currently in ${assignedCategory.name} - ${_accountLabel(room)}'
            : _accountLabel(room),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      value: assignedHere,
      onChanged: _saving
          ? null
          : (selected) {
              if (selected == true) {
                _assignRoomToCategory(room.favoriteStorageId, category.id);
              } else {
                _unassignRoom(room.favoriteStorageId);
              }
            },
    );
  }

  String _accountLabel(Room room) {
    final self = room.client.self;
    final identifier = self?.identifier ?? room.client.identifier;
    return '$identifier - ${room.favoriteStorageId}';
  }

  SpaceRoomCategoryDefinition? _categoryForRoom(String roomId) {
    for (final category in _state.categories) {
      if (category.roomIds.contains(roomId)) {
        return category;
      }
    }

    return null;
  }

  Future<void> _createCategory() async {
    final name = await AdaptiveDialog.textPrompt(
      context,
      title: 'Add Category',
      hintText: 'Category name',
      submitText: 'Add',
    );
    if (!mounted || name == null) {
      return;
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return;
    }

    await _runSaving(
      () => spaceRoomCategoryStore.createCategory(
        favoriteRoomCategoriesLocalId,
        trimmedName,
      ),
    );
  }

  Future<void> _renameCategory(SpaceRoomCategoryDefinition category) async {
    final name = await AdaptiveDialog.textPrompt(
      context,
      title: 'Rename Category',
      hintText: category.name,
      initialText: category.name,
      submitText: 'Save',
    );
    if (!mounted || name == null || name.trim().isEmpty) {
      return;
    }
    final trimmedName = name.trim();

    await _runSaving(
      () => spaceRoomCategoryStore.renameCategory(
        favoriteRoomCategoriesLocalId,
        category.id,
        trimmedName,
      ),
    );
  }

  Future<void> _deleteCategory(SpaceRoomCategoryDefinition category) async {
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: 'Delete Category',
      prompt:
          'Delete ${category.name}? Favorite rooms in this category will move back to Uncategorized.',
      dangerous: true,
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await _runSaving(
      () => spaceRoomCategoryStore.deleteCategory(
        favoriteRoomCategoriesLocalId,
        category.id,
      ),
    );
  }

  Future<void> _moveCategory(SpaceRoomCategoryDefinition category, int index) {
    return _runSaving(
      () => spaceRoomCategoryStore.moveCategory(
        favoriteRoomCategoriesLocalId,
        category.id,
        index,
      ),
    );
  }

  Future<void> _setCategoryCollapsed(
    SpaceRoomCategoryDefinition category,
    bool collapsed,
  ) {
    return _runSaving(
      () => spaceRoomCategoryStore.setCategoryCollapsed(
        favoriteRoomCategoriesLocalId,
        category.id,
        collapsed,
      ),
    );
  }

  Future<void> _assignRoomToCategory(String roomId, String categoryId) {
    return _runSaving(
      () => spaceRoomCategoryStore.assignRoomToCategory(
        favoriteRoomCategoriesLocalId,
        roomId,
        categoryId,
      ),
    );
  }

  Future<void> _unassignRoom(String roomId) {
    return _runSaving(
      () => spaceRoomCategoryStore.unassignRoom(
        favoriteRoomCategoriesLocalId,
        roomId,
      ),
    );
  }

  Future<void> _runSaving(Future<dynamic> Function() action) async {
    if (_saving) {
      return;
    }

    setState(() => _saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Unable to save favorite category changes.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
