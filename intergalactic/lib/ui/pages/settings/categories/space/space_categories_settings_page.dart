import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/space_room_categories.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceCategoriesSettingsPage extends StatefulWidget {
  const SpaceCategoriesSettingsPage({
    required this.space,
    super.key,
  });

  final Space space;

  @override
  State<SpaceCategoriesSettingsPage> createState() =>
      _SpaceCategoriesSettingsPageState();
}

class _SpaceCategoriesSettingsPageState
    extends State<SpaceCategoriesSettingsPage> {
  SpaceRoomCategoryState _state = SpaceRoomCategoryState.empty;
  StreamSubscription? _storeSubscription;
  StreamSubscription? _spaceSubscription;
  bool _loaded = false;
  bool _saving = false;

  bool get _canManage => canManageSpaceRoomCategories(widget.space);

  List<Room> get _rooms => widget.space.rooms;

  String get _spaceLocalId => widget.space.localId;

  @override
  void initState() {
    super.initState();
    _loadState();
    _subscribeToUpdates();
  }

  @override
  void didUpdateWidget(covariant SpaceCategoriesSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.space.localId != widget.space.localId) {
      _cancelSubscriptions();
      _loaded = false;
      _loadState();
      _subscribeToUpdates();
    }
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  Future<void> _loadState() async {
    final state = await spaceRoomCategoryStore.loadForSpace(widget.space);
    if (!mounted) {
      return;
    }

    setState(() {
      _state = state.normalizedForRoomIds(
        _rooms.map((room) => room.identifier),
      );
      _loaded = true;
    });
  }

  void _subscribeToUpdates() {
    _storeSubscription = spaceRoomCategoryStore.onChanged
        .where((event) => event.spaceLocalId == _spaceLocalId)
        .listen(_onCategoryStateChanged);
    _spaceSubscription = widget.space.onUpdate.listen((_) => _loadState());
  }

  void _cancelSubscriptions() {
    _storeSubscription?.cancel();
    _storeSubscription = null;
    _spaceSubscription?.cancel();
    _spaceSubscription = null;
  }

  void _onCategoryStateChanged(SpaceRoomCategoryChanged event) {
    if (!mounted) {
      return;
    }

    setState(() {
      _state = event.state.normalizedForRoomIds(
        _rooms.map((room) => room.identifier),
      );
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = _state.categories;
    final unassignedRooms = _rooms
        .where((room) => _categoryForRoom(room.identifier) == null)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Room Categories',
          children: [
            SettingsControlRow(
              title: 'Shared room groups',
              description: _canManage
                  ? 'Categories are shared with Inter Galactic users in this space. They do not create, remove, or reorder Matrix space rooms.'
                  : 'Categories are shared by space admins. You can collapse groups locally, but only admins can change names, order, or room assignments.',
              trailing: _canManage
                  ? ElevatedButton.icon(
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Add category'),
                      onPressed: _saving ? null : _createCategory,
                    )
                  : null,
              child: !_loaded
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_canManage) _permissionNotice(),
                        if (categories.isEmpty)
                          tiamat.Text.labelLow(
                            _canManage
                                ? 'No categories yet. Add one to group rooms in the space sidebar for Inter Galactic users.'
                                : 'No shared categories have been created for this space.',
                          )
                        else ...[
                          tiamat.Text.labelLow(
                            unassignedRooms.isEmpty
                                ? 'All joined rooms are assigned to a shared category.'
                                : '${unassignedRooms.length} joined room${unassignedRooms.length == 1 ? '' : 's'} will stay in Uncategorized.',
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

  Widget _permissionNotice() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: tiamat.Text.labelLow(
        'Your current space role can view shared categories and choose local collapse state, but cannot change category names, order, or room assignments.',
      ),
    );
  }

  Widget _categoryCard(
    SpaceRoomCategoryDefinition category,
    int index,
    int categoryCount,
  ) {
    final theme = Theme.of(context);
    final assignedCurrentRooms = _rooms
        .where((room) => category.roomIds.contains(room.identifier))
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
              Row(
                children: [
                  Icon(
                    category.collapsed
                        ? Icons.folder_outlined
                        : Icons.folder_open_outlined,
                    size: 20,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      category.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  tiamat.Text.labelLow(
                    '$assignedCurrentRooms room${assignedCurrentRooms == 1 ? '' : 's'}',
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: category.collapsed
                        ? 'Expand locally in sidebar'
                        : 'Collapse locally in sidebar',
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
                  if (_canManage) ...[
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
                      onPressed:
                          _saving ? null : () => _renameCategory(category),
                    ),
                    IconButton(
                      tooltip: 'Delete category',
                      icon: const Icon(Icons.delete_outline),
                      color: theme.colorScheme.error,
                      onPressed:
                          _saving ? null : () => _deleteCategory(category),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              if (_rooms.isEmpty)
                tiamat.Text.labelLow(
                  'Join rooms in this space before assigning category membership.',
                )
              else
                Column(
                  children: [
                    for (final room in _rooms)
                      _roomAssignmentTile(category: category, room: room),
                  ],
                ),
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
    final assignedCategory = _categoryForRoom(room.identifier);
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
            ? 'Currently in ${assignedCategory.name} - ${room.identifier}'
            : room.identifier,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      value: assignedHere,
      onChanged: !_canManage || _saving
          ? null
          : (selected) {
              if (selected == true) {
                _assignRoomToCategory(room.identifier, category.id);
              } else {
                _unassignRoom(room.identifier);
              }
            },
    );
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

    await _runSaving(
      () => spaceRoomCategoryStore.createCategoryForSpace(widget.space, name),
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

    await _runSaving(
      () => spaceRoomCategoryStore.renameCategoryForSpace(
        widget.space,
        category.id,
        name,
      ),
    );
  }

  Future<void> _deleteCategory(SpaceRoomCategoryDefinition category) async {
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: 'Delete Category',
      prompt:
          'Delete ${category.name}? Rooms in this category will move back to Uncategorized.',
      dangerous: true,
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await _runSaving(
      () => spaceRoomCategoryStore.deleteCategoryForSpace(
        widget.space,
        category.id,
      ),
    );
  }

  Future<void> _moveCategory(
    SpaceRoomCategoryDefinition category,
    int index,
  ) {
    return _runSaving(
      () => spaceRoomCategoryStore.moveCategoryForSpace(
        widget.space,
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
      () => spaceRoomCategoryStore.setCategoryCollapsedForSpace(
        widget.space,
        category.id,
        collapsed,
      ),
    );
  }

  Future<void> _assignRoomToCategory(String roomId, String categoryId) {
    return _runSaving(
      () => spaceRoomCategoryStore.assignRoomToCategoryForSpace(
        widget.space,
        roomId,
        categoryId,
      ),
    );
  }

  Future<void> _unassignRoom(String roomId) {
    return _runSaving(
      () => spaceRoomCategoryStore.unassignRoomForSpace(
        widget.space,
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
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
