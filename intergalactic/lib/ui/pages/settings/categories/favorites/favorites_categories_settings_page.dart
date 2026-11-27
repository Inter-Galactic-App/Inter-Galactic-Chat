import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/favorite_room_categories.dart';
import 'package:intergalactic/client/favorite_rooms.dart';
import 'package:intergalactic/client/space_room_categories.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/category_settings_header.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:uuid/uuid.dart';

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
  Client? _selectedClient;
  late final List<StreamSubscription> _subscriptions;
  bool _loaded = false;
  bool _saving = false;

  List<Client> get _favoriteClients {
    final clients = <Client>[];
    for (final room in widget.clientManager.rooms) {
      if (favoriteRoomStore.isFavorite(room) &&
          !clients.contains(room.client)) {
        clients.add(room.client);
      }
    }
    return clients;
  }

  List<Room> get _favoriteRooms => favoriteRoomStore.sortFavorites(
    widget.clientManager.rooms.where(
      (room) =>
          room.client == _selectedClient && favoriteRoomStore.isFavorite(room),
    ),
  );

  @override
  void initState() {
    super.initState();
    _subscriptions = [
      favoriteRoomCategoryStore.onChanged.listen(_onCategoryStateChanged),
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
    final clients = _favoriteClients;
    if (_selectedClient == null || !clients.contains(_selectedClient)) {
      final nextClient = clients.isEmpty ? null : clients.first;
      if (nextClient != _selectedClient) {
        _selectedClient = nextClient;
        _state = SpaceRoomCategoryState.empty;
        _loaded = false;
      }
    }
    final client = _selectedClient;
    if (client == null) {
      if (mounted) {
        setState(() {
          _state = SpaceRoomCategoryState.empty;
          _loaded = true;
        });
      }
      return;
    }
    final favoriteRoomIds = _favoriteRooms
        .map((room) => room.favoriteStorageId)
        .toList(growable: false);
    final state = await favoriteRoomCategoryStore.load(
      client: client,
      favoriteRoomIds: favoriteRoomIds,
    );
    if (!mounted || client != _selectedClient) {
      return;
    }

    setState(() {
      _state = state.normalizedForRoomIds(
        _favoriteRooms.map((room) => room.favoriteStorageId),
      );
      _loaded = true;
    });
  }

  void _onCategoryStateChanged(FavoriteRoomCategoryChanged event) {
    if (!mounted || event.client != _selectedClient) {
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
              title: 'Account-wide favorite groups',
              description:
                  'Categories sync through Matrix account data for this account. Each signed-in account keeps its own separate groups.',
              trailing: ElevatedButton.icon(
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add category'),
                onPressed: _saving || !_loaded ? null : _createCategory,
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
                        if (_favoriteClients.length > 1) ...[
                          DropdownButton<Client>(
                            isExpanded: true,
                            value: _selectedClient,
                            items: [
                              for (final client in _favoriteClients)
                                DropdownMenuItem(
                                  value: client,
                                  child: Text(_clientLabel(client)),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (client) {
                                    if (client == null) return;
                                    setState(() {
                                      _selectedClient = client;
                                      _state = SpaceRoomCategoryState.empty;
                                      _loaded = false;
                                    });
                                    unawaited(_loadState());
                                  },
                          ),
                          const SizedBox(height: 12),
                        ],
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
                                'Add a category for this Matrix account.',
                            padding: EdgeInsets.zero,
                            action: ElevatedButton.icon(
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                              ),
                              label: const Text('Add category'),
                              onPressed: _saving || !_loaded
                                  ? null
                                  : _createCategory,
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

  String _clientLabel(Client client) {
    final self = client.self;
    return self?.identifier ?? client.identifier;
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
    if (!_loaded) return;
    final client = _selectedClient;
    final name = await AdaptiveDialog.textPrompt(
      context,
      title: 'Add Category',
      hintText: 'Category name',
      submitText: 'Add',
    );
    if (!mounted || !_loaded || client != _selectedClient || name == null) {
      return;
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return;
    }

    await _runSaving(
      () => _saveState(
        _state.copyWith(
          categories: [
            ..._state.categories,
            SpaceRoomCategoryDefinition(
              id: const Uuid().v4(),
              name: normalizeSpaceRoomCategoryName(trimmedName),
            ),
          ],
        ),
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
      () => _saveState(
        _state.copyWith(
          categories: [
            for (final value in _state.categories)
              if (value.id == category.id)
                value.copyWith(
                  name: normalizeSpaceRoomCategoryName(trimmedName),
                )
              else
                value,
          ],
        ),
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
      () => _saveState(
        _state.copyWith(
          categories: [
            for (final value in _state.categories)
              if (value.id != category.id) value,
          ],
        ),
      ),
    );
  }

  Future<void> _moveCategory(SpaceRoomCategoryDefinition category, int index) {
    final categories = List<SpaceRoomCategoryDefinition>.from(
      _state.categories,
    );
    final oldIndex = categories.indexWhere((value) => value.id == category.id);
    if (oldIndex < 0) return Future.value();
    final moved = categories.removeAt(oldIndex);
    categories.insert(index.clamp(0, categories.length).toInt(), moved);
    return _runSaving(
      () => _saveState(_state.copyWith(categories: categories)),
    );
  }

  Future<void> _setCategoryCollapsed(
    SpaceRoomCategoryDefinition category,
    bool collapsed,
  ) {
    return _runSaving(() async {
      final client = _selectedClient;
      if (client == null) return;
      final state = _state.copyWith(
        categories: [
          for (final value in _state.categories)
            if (value.id == category.id)
              value.copyWith(collapsed: collapsed)
            else
              value,
        ],
      );
      await favoriteRoomCategoryStore.saveLocalView(
        client: client,
        state: state,
      );
    });
  }

  Future<void> _assignRoomToCategory(String roomId, String categoryId) {
    return _runSaving(
      () => _saveState(
        _state.copyWith(
          categories: [
            for (final category in _state.categories)
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
      ),
    );
  }

  Future<void> _unassignRoom(String roomId) {
    return _runSaving(
      () => _saveState(
        _state.copyWith(
          categories: [
            for (final category in _state.categories)
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
      ),
    );
  }

  Future<void> _saveState(SpaceRoomCategoryState state) async {
    final client = _selectedClient;
    if (client == null || !_loaded) return;
    await favoriteRoomCategoryStore.save(client: client, state: state);
  }

  Future<void> _runSaving(Future<dynamic> Function() action) async {
    if (_saving || !_loaded) {
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
