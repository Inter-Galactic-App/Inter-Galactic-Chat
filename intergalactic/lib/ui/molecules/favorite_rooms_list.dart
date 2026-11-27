import 'dart:async';
import 'dart:ui';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/favorite_room_categories.dart';
import 'package:intergalactic/client/favorite_rooms.dart';
import 'package:intergalactic/client/space_room_categories.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:intergalactic/ui/atoms/adaptive_context_menu.dart';
import 'package:intergalactic/ui/atoms/favorite_room_actions.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/atoms/room_text_button.dart';
import 'package:intergalactic/ui/atoms/room_panel.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/pages/settings/favorites_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/favorites/settings_category_favorites.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/preference_image_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

enum FavoriteRoomsListLayout { adaptive, summary, mobileSidebar }

class FavoriteRoomsList extends StatefulWidget {
  const FavoriteRoomsList({
    super.key,
    required this.clientManager,
    this.filterClient,
    this.onRoomSelected,
    this.emptyMessage = "Star a room to add it to Favorites.",
    this.showHeader = false,
    this.header = "Favorites",
    this.layout = FavoriteRoomsListLayout.adaptive,
    this.roomIndicatorTrailingInset = 0,
  });

  final ClientManager clientManager;
  final Client? filterClient;
  final Function(Room room, {bool bypassSpecialRoomType})? onRoomSelected;
  final String emptyMessage;
  final bool showHeader;
  final String header;
  final FavoriteRoomsListLayout layout;
  final double roomIndicatorTrailingInset;

  @override
  State<FavoriteRoomsList> createState() => _FavoriteRoomsListState();
}

class _FavoriteRoomsListState extends State<FavoriteRoomsList> {
  static const double _spaceSummaryBreakpoint = 520;

  late final List<StreamSubscription> subscriptions;
  Room? selectedRoom;
  bool orderChanged = false;
  bool orderChangeLoading = false;
  List<String>? reorderedFavoriteIds;
  Map<Client, SpaceRoomCategoryState> favoriteCategoryStates = {};
  Map<String, _FavoriteCategoryGroup> _favoriteGroupsById = {};
  bool favoriteCategoryStateLoaded = false;
  String? _cachedFavoritesBannerImageData;
  ImageProvider? _cachedFavoritesBannerImage;
  String? _cachedFavoritesIconImageData;
  ImageProvider? _cachedFavoritesIconImage;

  @override
  void initState() {
    super.initState();
    subscriptions = [
      EventBus.onSelectedRoomChanged.stream.listen((room) {
        if (mounted) {
          setState(() {
            selectedRoom = room;
          });
        }
      }),
      preferences.onSettingChanged.listen((_) {
        if (mounted) {
          setState(() {
            if (!orderChanged) {
              reorderedFavoriteIds = null;
            }
          });
        }
      }),
      widget.clientManager.onRoomAdded.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
      widget.clientManager.onRoomRemoved.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
      widget.clientManager.onClientUpdated.stream.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
      favoriteRoomCategoryStore.onChanged.listen(
        _onFavoriteCategoryStateChanged,
      ),
      favoriteRoomStore.onChanged.listen((_) => _reconcileFavorites()),
      // Membership lives in m.tag account data now, so a favourite added or
      // removed on another device arrives in a sync and touches no local
      // preference. onSettingChanged above cannot see it.
      widget.clientManager.onSync.stream.listen((_) => _reconcileFavorites()),
    ];
    unawaited(_loadFavoriteCategoryState());
  }

  @override
  void dispose() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Set<String> _lastFavoriteIds = {};
  void _reconcileFavorites() {
    if (!mounted) {
      return;
    }

    final ids = favoriteRooms.map((room) => room.favoriteStorageId).toSet();
    if (setEquals(ids, _lastFavoriteIds)) {
      return;
    }

    setState(() {
      _lastFavoriteIds = ids;
    });
    unawaited(_loadFavoriteCategoryState());
  }

  List<Room> get favoriteRooms {
    final rooms = widget.clientManager.rooms.where((room) {
      if (widget.filterClient != null && room.client != widget.filterClient) {
        return false;
      }

      return favoriteRoomStore.isFavorite(room);
    }).toList();

    // A drag in progress. Its order is not persisted anywhere yet, so it has
    // to win over both the tag order and the stored list until it is saved or
    // reset.
    final pendingIds = reorderedFavoriteIds;
    if (pendingIds == null) {
      return favoriteRoomStore.sortFavorites(rooms);
    }

    final order = <String, int>{
      for (var i = 0; i < pendingIds.length; i++) pendingIds[i]: i,
    };

    int sortOrder(Room room) {
      final stableOrder = order[room.favoriteStorageId];
      final legacyOrder = order[room.localId];
      if (stableOrder == null) return legacyOrder ?? pendingIds.length;
      if (legacyOrder == null) return stableOrder;
      return stableOrder < legacyOrder ? stableOrder : legacyOrder;
    }

    rooms.sort((a, b) => sortOrder(a).compareTo(sortOrder(b)));

    return rooms;
  }

  bool get _shouldUseFavoriteCategories =>
      favoriteCategoryStateLoaded &&
      favoriteCategoryStates.values.any((state) => state.hasCategories);

  Future<void> _loadFavoriteCategoryState() async {
    final roomsByClient = <Client, List<Room>>{};
    for (final room in favoriteRooms) {
      (roomsByClient[room.client] ??= []).add(room);
    }
    final states = <Client, SpaceRoomCategoryState>{};
    for (final entry in roomsByClient.entries) {
      states[entry.key] =
          (await favoriteRoomCategoryStore.load(
            client: entry.key,
            favoriteRoomIds: entry.value.map((room) => room.favoriteStorageId),
          )).normalizedForRoomIds(
            entry.value.map((room) => room.favoriteStorageId),
          );
    }
    if (!mounted) {
      return;
    }

    setState(() {
      favoriteCategoryStates = states;
      favoriteCategoryStateLoaded = true;
    });
  }

  void _onFavoriteCategoryStateChanged(FavoriteRoomCategoryChanged event) {
    if (!mounted) {
      return;
    }

    setState(() {
      final roomIds = favoriteRooms
          .where((room) => room.client == event.client)
          .map((room) => room.favoriteStorageId);
      favoriteCategoryStates = {
        ...favoriteCategoryStates,
        event.client: event.state.normalizedForRoomIds(roomIds),
      };
      favoriteCategoryStateLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = favoriteRooms;

    if (widget.showHeader) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (widget.layout == FavoriteRoomsListLayout.summary) {
            return _buildSpaceSummarySurface(
              context,
              rooms,
              scrollable: constraints.maxHeight.isFinite,
            );
          }

          if (widget.layout == FavoriteRoomsListLayout.mobileSidebar) {
            final canExpandHeight = constraints.maxHeight.isFinite;
            final sidebar = _buildMobileSidebarSpaceSurface(
              context,
              rooms,
              expandHeight: canExpandHeight,
            );

            if (!canExpandHeight) {
              return sidebar;
            }

            return SizedBox(height: constraints.maxHeight, child: sidebar);
          }

          final shouldUseSpaceSummary =
              constraints.maxWidth.isFinite &&
              constraints.maxWidth >= _spaceSummaryBreakpoint;

          if (shouldUseSpaceSummary) {
            return _buildSpaceSummarySurface(
              context,
              rooms,
              scrollable: constraints.maxHeight.isFinite,
            );
          }

          final canExpandHeight = constraints.maxHeight.isFinite;
          final sidebar = _buildSidebarSpaceSurface(
            rooms,
            expandHeight: canExpandHeight,
          );

          if (!canExpandHeight) {
            return sidebar;
          }

          return SizedBox(height: constraints.maxHeight, child: sidebar);
        },
      );
    }

    return _buildSidebarFavoritesBody(rooms);
  }

  Widget _buildSpaceSummarySurface(
    BuildContext context,
    List<Room> rooms, {
    required bool scrollable,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final countLabel = _roomCountLabel(rooms.length);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSpaceSummaryBanner(context),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        tiamat.Text.labelLow('Welcome to'),
                        const SizedBox(height: 8),
                        Text(
                          widget.header,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 20,
                              color: colorScheme.secondary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: tiamat.Text.label(
                                'Favorites',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softwrap: false,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _buildFavoritesSettingsButton(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              tiamat.Panel(
                mode: tiamat.TileType.surfaceContainerLow,
                mainAxisSize: MainAxisSize.min,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FavoriteSummaryHeader(
                      title: 'Favorites',
                      countLabel: countLabel,
                    ),
                    _buildSummaryFavoritesBody(rooms),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return scrollable ? SingleChildScrollView(child: content) : content;
  }

  Widget _buildFavoritesSettingsButton() {
    return tiamat.Tooltip(
      text: 'Favorites settings',
      preferredDirection: AxisDirection.left,
      child: tiamat.CircleButton(
        icon: Icons.settings,
        radius: Layout.mobile ? 24 : 16,
        onPressed: _openFavoritesSettings,
      ),
    );
  }

  Future<void> _openFavoritesSettings() {
    return SettingsNavigation.show(
      context,
      FavoritesSettingsPage(
        clientManager: widget.clientManager,
        initialTabId: SettingsCategoryFavorites.tabIdAppearance,
      ),
    );
  }

  Widget _buildSidebarSpaceSurface(
    List<Room> rooms, {
    required bool expandHeight,
  }) {
    final body = _buildSidebarFavoritesBody(rooms);

    Widget header = _FavoriteSidebarHeader(
      title: widget.header,
      bannerImage: _favoritesBannerImage(),
    );

    // The compact/mobile Favorites virtual-space surface never reaches the
    // wide space-summary layout, so the Favorites settings gear (icon, banner
    // and local categories) would otherwise be unreachable on phones. Surface
    // it directly on the header for mobile widths.
    if (Layout.mobile) {
      header = Stack(
        children: [
          header,
          Positioned(top: 6, right: 6, child: _buildFavoritesSettingsButton()),
        ],
      );
    }

    return Column(
      mainAxisSize: expandHeight ? MainAxisSize.max : MainAxisSize.min,
      children: [
        header,
        const SizedBox(height: 12),
        if (expandHeight)
          Expanded(child: SingleChildScrollView(child: body))
        else
          body,
      ],
    );
  }

  Widget _buildMobileSidebarSpaceSurface(
    BuildContext context,
    List<Room> rooms, {
    required bool expandHeight,
  }) {
    final body = Padding(
      padding: const EdgeInsets.all(8),
      child: _buildMobileSidebarFavoritesBody(
        rooms,
        expandHeight: expandHeight,
      ),
    );

    return Column(
      mainAxisSize: expandHeight ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _FavoriteSidebarHeader(
          title: widget.header,
          bannerImage: _favoritesBannerImage(),
        ),
        if (expandHeight) Expanded(child: body) else body,
      ],
    );
  }

  Widget _buildSpaceSummaryBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bannerImage = _favoritesBannerImage();
    final iconImage = _favoritesIconImage();

    return Stack(
      children: [
        Padding(
          padding: Layout.desktop
              ? const EdgeInsets.only(left: 8, right: 8)
              : EdgeInsets.zero,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bannerImage == null ? colorScheme.secondary : null,
              image: bannerImage == null
                  ? null
                  : DecorationImage(image: bannerImage, fit: BoxFit.cover),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(15),
                bottomRight: Radius.circular(15),
              ),
            ),
            child: const ScaledSafeArea(
              bottom: false,
              left: false,
              right: false,
              top: true,
              child: SizedBox(height: 250, width: double.infinity),
            ),
          ),
        ),
        Align(
          alignment: AlignmentGeometry.center,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 150, 0, 0),
            child: ScaledSafeArea(
              child: tiamat.Avatar.extraLarge(
                image: iconImage,
                border: BoxBorder.all(
                  color: colorScheme.surface,
                  width: 10,
                  style: BorderStyle.solid,
                  strokeAlign: 0.5,
                ),
                placeholderText: widget.header,
                placeholderColor: colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _roomCountLabel(int count) {
    return '$count room${count == 1 ? '' : 's'}';
  }

  ImageProvider? _favoritesBannerImage() {
    final imageData = preferences.favoritesBannerImageData.value;
    if (_cachedFavoritesBannerImageData == imageData) {
      return _cachedFavoritesBannerImage;
    }

    _cachedFavoritesBannerImageData = imageData;
    final bytes = decodePreferenceImageData(imageData);
    return _cachedFavoritesBannerImage = bytes == null
        ? null
        : MemoryImage(bytes);
  }

  ImageProvider? _favoritesIconImage() {
    final imageData = preferences.favoritesIconImageData.value;
    if (_cachedFavoritesIconImageData == imageData) {
      return _cachedFavoritesIconImage;
    }

    _cachedFavoritesIconImageData = imageData;
    final bytes = decodePreferenceImageData(imageData);
    return _cachedFavoritesIconImage = bytes == null
        ? null
        : MemoryImage(bytes);
  }

  Widget _buildSidebarFavoritesBody(List<Room> rooms) {
    if (rooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: tiamat.Text.labelLow(widget.emptyMessage),
      );
    }

    if (_shouldUseFavoriteCategories) {
      return Column(
        children: [
          for (final group in _buildFavoriteCategoryGroups(rooms))
            _FavoriteSpaceSection(
              id: group.id,
              name: group.name,
              collapsed: group.collapsed,
              onCollapsedChanged: (collapsed) {
                unawaited(_setFavoriteGroupCollapsed(group, collapsed));
              },
              children: [
                for (final room in group.rooms)
                  RoomTextButton(
                    room,
                    onTap: widget.onRoomSelected,
                    highlight: selectedRoom == room,
                    trailingIndicatorInset: widget.roomIndicatorTrailingInset,
                  ),
              ],
            ),
        ],
      );
    }

    return ImplicitlyAnimatedList(
      itemData: rooms,
      shrinkWrap: true,
      initialAnimation: false,
      padding: const EdgeInsets.all(0),
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, room) {
        return RoomTextButton(
          room,
          onTap: widget.onRoomSelected,
          highlight: selectedRoom == room,
          trailingIndicatorInset: widget.roomIndicatorTrailingInset,
        );
      },
    );
  }

  Widget _buildMobileSidebarFavoritesBody(
    List<Room> rooms, {
    required bool expandHeight,
  }) {
    if (rooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: tiamat.Text.labelLow(widget.emptyMessage),
      );
    }

    if (_shouldUseFavoriteCategories) {
      final children = [
        for (final group in _buildFavoriteCategoryGroups(rooms))
          _FavoriteSpaceSection(
            id: group.id,
            name: group.name,
            collapsed: group.collapsed,
            onCollapsedChanged: (collapsed) {
              unawaited(_setFavoriteGroupCollapsed(group, collapsed));
            },
            children: [_buildMobileSidebarFavoriteCategoryOrderList(group)],
          ),
      ];

      if (expandHeight) {
        return ListView(padding: EdgeInsets.zero, children: children);
      }

      return Column(children: children);
    }

    return ReorderableListView.builder(
      itemCount: rooms.length,
      shrinkWrap: !expandHeight,
      buildDefaultDragHandles: false,
      padding: EdgeInsets.zero,
      physics: expandHeight ? null : const NeverScrollableScrollPhysics(),
      proxyDecorator: _reorderProxyDecorator,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorder: _onMobileSidebarFavoriteReorder,
      itemBuilder: (context, index) {
        final room = rooms[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(
            'favorites-mobile-sidebar-room:${room.favoriteStorageId}',
          ),
          index: index,
          enabled: !orderChangeLoading,
          child: RoomTextButton(
            room,
            onTap: widget.onRoomSelected,
            highlight: selectedRoom == room,
            trailingIndicatorInset: widget.roomIndicatorTrailingInset,
            enableContextMenu: false,
          ),
        );
      },
    );
  }

  Widget _buildMobileSidebarFavoriteCategoryOrderList(
    _FavoriteCategoryGroup group,
  ) {
    return ReorderableListView.builder(
      key: ValueKey('favorites-mobile-sidebar-category:${group.id}'),
      itemCount: group.rooms.length,
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      proxyDecorator: _reorderProxyDecorator,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorder: (oldIndex, newIndex) {
        if (!orderChangeLoading) {
          unawaited(
            _onFavoriteCategoryReorder(
              group.id,
              group.rooms,
              oldIndex,
              newIndex,
            ),
          );
        }
      },
      itemBuilder: (context, index) {
        final room = group.rooms[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(
            'favorites-mobile-sidebar-category-room:'
            '${group.id}:${room.favoriteStorageId}',
          ),
          index: index,
          enabled: !orderChangeLoading,
          child: RoomTextButton(
            room,
            onTap: widget.onRoomSelected,
            highlight: selectedRoom == room,
            trailingIndicatorInset: widget.roomIndicatorTrailingInset,
            enableContextMenu: false,
          ),
        );
      },
    );
  }

  Widget _buildSummaryFavoritesBody(List<Room> rooms) {
    if (rooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: tiamat.Text.labelLow(widget.emptyMessage),
      );
    }

    if (_shouldUseFavoriteCategories) {
      final groups = _buildFavoriteCategoryGroups(rooms);

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final group in groups)
            _FavoriteSpaceSection(
              id: group.id,
              name: _categorySummaryLabel(group),
              collapsed: group.collapsed,
              onCollapsedChanged: (collapsed) {
                unawaited(_setFavoriteGroupCollapsed(group, collapsed));
              },
              children: [
                _buildSummaryFavoriteRoomOrderList(
                  group.rooms,
                  groupId: group.id,
                ),
              ],
            ),
        ],
      );
    }

    return _buildSummaryFavoriteRoomOrderList(rooms);
  }

  Widget _buildSummaryFavoriteRoomOrderList(
    List<Room> rooms, {
    String? groupId,
  }) {
    final showHandles = Layout.desktop && !orderChangeLoading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReorderableListView.builder(
          itemCount: rooms.length,
          shrinkWrap: true,
          buildDefaultDragHandles: showHandles,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          proxyDecorator: _reorderProxyDecorator,
          onReorderStart: (_) => HapticFeedback.mediumImpact(),
          onReorder: (oldIndex, newIndex) {
            if (!orderChangeLoading) {
              if (groupId == null) {
                _onFavoriteReorder(oldIndex, newIndex);
              } else {
                unawaited(
                  _onFavoriteCategoryReorder(
                    groupId,
                    rooms,
                    oldIndex,
                    newIndex,
                  ),
                );
              }
            }
          },
          itemBuilder: (context, index) {
            final room = rooms[index];
            final dragEnabled =
                (groupId != null || orderChanged) && !orderChangeLoading;
            final key = ValueKey(
              'favorites-room:${groupId ?? 'all'}:${room.favoriteStorageId}',
            );
            final child = Padding(
              padding: EdgeInsets.fromLTRB(6, 2, showHandles ? 48 : 6, 2),
              // Space rows reserve a mobile long press for reordering. Keep
              // Favorites on that same gesture contract instead of letting its
              // desktop context menu claim the pointer first.
              child: _buildSummaryFavoriteRoom(
                room,
                enableContextMenu: !Layout.mobile,
              ),
            );

            if (Layout.mobile) {
              return ReorderableDelayedDragStartListener(
                key: key,
                index: index,
                enabled: !orderChangeLoading,
                child: child,
              );
            }

            return ReorderableDragStartListener(
              key: key,
              index: index,
              enabled: dragEnabled,
              child: child,
            );
          },
        ),
        if (groupId == null) _buildOrderActions(),
      ],
    );
  }

  List<_FavoriteCategoryGroup> _buildFavoriteCategoryGroups(List<Room> rooms) {
    final roomsByClient = <Client, List<Room>>{};
    for (final room in rooms) {
      (roomsByClient[room.client] ??= []).add(room);
    }
    final showAccountLabel = roomsByClient.length > 1;
    final groups = <_FavoriteCategoryGroup>[];
    for (final entry in roomsByClient.entries) {
      final state = favoriteCategoryStates[entry.key];
      if (state == null) continue;
      for (final group in buildSpaceRoomCategoryGroups<Room>(
        state: state,
        rooms: entry.value,
        roomId: (room) => room.favoriteStorageId,
        uncategorizedLabel: 'Uncategorized',
      )) {
        groups.add(
          _FavoriteCategoryGroup(
            client: entry.key,
            category: group,
            showAccountLabel: showAccountLabel,
          ),
        );
      }
    }
    _favoriteGroupsById = {for (final group in groups) group.id: group};
    return groups;
  }

  String _categorySummaryLabel(_FavoriteCategoryGroup group) {
    final count = group.rooms.length;
    return '${group.name}  ${count == 1 ? '1 room' : '$count rooms'}';
  }

  Future<void> _setFavoriteGroupCollapsed(
    _FavoriteCategoryGroup group,
    bool collapsed,
  ) async {
    final state = favoriteCategoryStates[group.client];
    if (state == null) return;
    final updated = group.isUncategorized
        ? state.copyWith(uncategorizedCollapsed: collapsed)
        : state.copyWith(
            categories: [
              for (final category in state.categories)
                if (category.id == group.category.id)
                  category.copyWith(collapsed: collapsed)
                else
                  category,
            ],
          );
    await favoriteRoomCategoryStore.saveLocalView(
      client: group.client,
      state: updated,
    );
  }

  Future<void> _onFavoriteCategoryReorder(
    String groupId,
    List<Room> rooms,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final orderedRooms = List<Room>.from(rooms);
    final room = orderedRooms.removeAt(oldIndex);
    orderedRooms.insert(newIndex, room);
    final group = _favoriteGroupsById[groupId];
    if (group == null) return;
    final state = favoriteCategoryStates[group.client];
    if (state == null) return;
    final updatedState = state.withExplicitRoomOrder(
      group.category.id,
      orderedRooms.map((room) => room.favoriteStorageId).toList(),
    );

    setState(() {
      favoriteCategoryStates = {
        ...favoriteCategoryStates,
        group.client: updatedState,
      };
    });
    await favoriteRoomCategoryStore.save(
      client: group.client,
      state: updatedState,
    );
  }

  Widget _buildSummaryFavoriteRoom(
    Room room, {
    required bool enableContextMenu,
  }) {
    final masked = dmLockController.shouldMaskRoomPreview(room);
    final lastEvent = room.lastEvent;

    Widget result = RoomPanel(
      displayName: room.displayName,
      avatar: room.avatar,
      color: room.defaultColor,
      onTap: orderChanged ? null : () => widget.onRoomSelected?.call(room),
      body: masked
          ? dmLockController.maskedPreviewText
          : lastEvent?.plainTextBody,
      recentEventSender: !masked && lastEvent != null
          ? room.getMemberOrFallback(lastEvent.senderId).displayName
          : null,
      recentEventSenderColor: !masked && lastEvent != null
          ? room.getColorOfUser(lastEvent.senderId)
          : null,
    );

    final items = [
      tiamat.ContextMenuItem(
        text: "Mark as Read",
        icon: Icons.visibility,
        onPressed: () => room.markAsRead(),
      ),
      tiamat.ContextMenuItem(
        text: "Remove from Favorites",
        icon: Icons.star_outline,
        onPressed: () async {
          await runFavoriteWrite(
            context,
            favoriteRoomStore.setFavorite(room, false),
          );
          if (mounted) {
            setState(() {});
          }
        },
      ),
      if (room.isSpecialRoomType)
        tiamat.ContextMenuItem(
          text: "Open as Text Chat",
          icon: Icons.tag,
          onPressed: () =>
              widget.onRoomSelected?.call(room, bypassSpecialRoomType: true),
        ),
    ];

    if (enableContextMenu) {
      result = AdaptiveContextMenu(items: items, child: result);
    }

    return result;
  }

  Widget _buildOrderActions() {
    if (!orderChanged) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          if (!orderChangeLoading)
            FloatingActionButton.small(
              onPressed: _resetFavoriteOrder,
              child: const Icon(Icons.undo),
            ),
          FloatingActionButton.small(
            onPressed: orderChangeLoading ? null : _saveFavoriteOrder,
            child: orderChangeLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  )
                : const Icon(Icons.save),
          ),
        ],
      ),
    );
  }

  void _onFavoriteReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final orderedRooms = List<Room>.from(favoriteRooms);
    final room = orderedRooms.removeAt(oldIndex);
    orderedRooms.insert(newIndex, room);

    setState(() {
      reorderedFavoriteIds = [
        for (final room in orderedRooms) room.favoriteStorageId,
      ];
      orderChanged = true;
    });
  }

  void _onMobileSidebarFavoriteReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final orderedRooms = List<Room>.from(favoriteRooms);
    final room = orderedRooms.removeAt(oldIndex);
    orderedRooms.insert(newIndex, room);
    final orderedIds = _mergeVisibleFavoriteOrder(
      orderedRooms.map((room) => room.favoriteStorageId).toList(),
    );

    setState(() {
      reorderedFavoriteIds = orderedIds;
      orderChanged = false;
      orderChangeLoading = true;
    });

    unawaited(_saveMobileSidebarFavoriteOrder(orderedIds));
  }

  Future<void> _saveMobileSidebarFavoriteOrder(List<String> orderedIds) async {
    try {
      final result = await favoriteRoomStore.setFavoriteOrder(
        orderedStorageIds: orderedIds,
        knownRooms: widget.clientManager.rooms,
      );
      if (mounted) {
        setState(() {
          orderChangeLoading = false;
          reorderedFavoriteIds = null;
        });
        if (result == FavoriteWriteResult.failed) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('Favorite order could not be saved.')),
          );
        }
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to save mobile sidebar favorite order',
      );
      if (mounted) {
        setState(() {
          orderChangeLoading = false;
          reorderedFavoriteIds = null;
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Favorite order could not be saved.')),
        );
      }
    }
  }

  void _resetFavoriteOrder() {
    setState(() {
      reorderedFavoriteIds = null;
      orderChanged = false;
      orderChangeLoading = false;
    });
  }

  Future<void> _saveFavoriteOrder() async {
    final visibleRooms = favoriteRooms;
    final currentVisibleIds = {
      for (final room in visibleRooms) room.favoriteStorageId,
    };
    final reorderedIds = reorderedFavoriteIds ?? const <String>[];
    final reorderedIdSet = reorderedIds.toSet();
    final visibleOrderedIds = [
      for (final id in reorderedIds)
        if (currentVisibleIds.contains(id)) id,
      for (final room in visibleRooms)
        if (!reorderedIdSet.contains(room.favoriteStorageId))
          room.favoriteStorageId,
    ];
    final orderedIds = _mergeVisibleFavoriteOrder(visibleOrderedIds);

    setState(() {
      orderChangeLoading = true;
    });

    try {
      final result = await favoriteRoomStore.setFavoriteOrder(
        orderedStorageIds: orderedIds,
        knownRooms: widget.clientManager.rooms,
      );
      if (!mounted) {
        return;
      }
      if (result == FavoriteWriteResult.failed) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Favorite order could not be saved.')),
        );
        return;
      }
      setState(() {
        orderChanged = false;
        reorderedFavoriteIds = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          orderChangeLoading = false;
        });
      }
    }
  }

  List<String> _mergeVisibleFavoriteOrder(List<String> visibleOrderedIds) {
    final visibleIdSet = visibleOrderedIds.toSet();
    final stableIdByKnownId = <String, String>{
      for (final room in widget.clientManager.rooms) ...{
        room.favoriteStorageId: room.favoriteStorageId,
        room.localId: room.favoriteStorageId,
      },
    };
    final previousIds = preferences.getFavoriteRoomIds();
    final orderedIds = <String>[];
    final addedIds = <String>{};
    final seenPreviousVisibleIds = <String>{};
    var visibleIndex = 0;

    for (final id in previousIds) {
      final normalizedId = stableIdByKnownId[id] ?? id;
      if (visibleIdSet.contains(normalizedId)) {
        if (seenPreviousVisibleIds.add(normalizedId) &&
            visibleIndex < visibleOrderedIds.length) {
          orderedIds.add(visibleOrderedIds[visibleIndex]);
          addedIds.add(visibleOrderedIds[visibleIndex]);
          visibleIndex += 1;
        }
      } else if (addedIds.add(normalizedId)) {
        orderedIds.add(normalizedId);
      }
    }

    while (visibleIndex < visibleOrderedIds.length) {
      final id = visibleOrderedIds[visibleIndex];
      if (addedIds.add(id)) {
        orderedIds.add(id);
      }
      visibleIndex += 1;
    }

    return orderedIds;
  }

  Widget _reorderProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final animValue = Curves.easeOut.transform(animation.value);
        final scale = lerpDouble(1, 1.03, animValue)!;
        return Transform.scale(scale: scale, child: child);
      },
      child: child,
    );
  }
}

class _FavoriteSidebarHeader extends StatelessWidget {
  const _FavoriteSidebarHeader({
    required this.title,
    required this.bannerImage,
  });

  final String title;
  final ImageProvider? bannerImage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasHeaderImage = bannerImage != null;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(8),
        bottomRight: Radius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints.expand(height: 100),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bannerImage != null)
              Image(
                image: bannerImage!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
            Material(
              color: bannerImage == null
                  ? colorScheme.primary
                  : Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: bannerImage == null
                      ? null
                      : LinearGradient(
                          begin: AlignmentGeometry.bottomCenter,
                          end: AlignmentGeometry.topCenter,
                          colors: [colorScheme.primary, Colors.transparent],
                        ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 2, 0, 2),
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colorScheme.onPrimary,
                                fontFamily: Layout.mobile ? "NunitoSans" : null,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                shadows: !hasHeaderImage
                                    ? null
                                    : [
                                        const Shadow(
                                          blurRadius: 12,
                                          color: Colors.black,
                                          offset: Offset(2, 2),
                                        ),
                                      ],
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteSummaryHeader extends StatelessWidget {
  const _FavoriteSummaryHeader({required this.title, required this.countLabel});

  final String title;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: tiamat.Text.labelEmphasised(
              title,
              color: theme.colorScheme.secondary,
            ),
          ),
          tiamat.Text.labelLow(countLabel),
        ],
      ),
    );
  }
}

class _FavoriteCategoryGroup {
  const _FavoriteCategoryGroup({
    required this.client,
    required this.category,
    required this.showAccountLabel,
  });

  final Client client;
  final SpaceRoomCategoryGroup<Room> category;
  final bool showAccountLabel;

  String get id => '${client.identifier}:${category.id}';
  String get name {
    if (!showAccountLabel) return category.name;
    final account = client.self?.identifier ?? client.identifier;
    return '$account · ${category.name}';
  }

  bool get collapsed => category.collapsed;
  bool get isUncategorized => category.isUncategorized;
  List<Room> get rooms => category.rooms;
}

class _FavoriteSpaceSection extends StatelessWidget {
  const _FavoriteSpaceSection({
    required this.id,
    required this.name,
    required this.collapsed,
    required this.children,
    required this.onCollapsedChanged,
  });

  final String id;
  final String name;
  final bool collapsed;
  final List<Widget> children;
  final ValueChanged<bool> onCollapsedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sectionColor = theme.colorScheme.secondary;
    final duration = InterGalacticMotion.duration(
      context,
      InterGalacticMotion.standard,
    );
    final toggleCollapsed = () => onCollapsedChanged(!collapsed);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AccessibleInteractiveRegion(
          semanticLabel: name,
          semanticValue: collapsed ? 'Collapsed' : 'Expanded',
          semanticHint: collapsed
              ? 'Expand favorites section'
              : 'Collapse favorites section',
          semanticOnTapHint: collapsed ? 'Expand section' : 'Collapse section',
          expanded: !collapsed,
          excludeChildSemantics: true,
          onActivate: toggleCollapsed,
          borderRadius: BorderRadius.circular(8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              excludeFromSemantics: true,
              canRequestFocus: false,
              onTap: toggleCollapsed,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: _FavoriteSpaceSectionHeader(
                        name: name,
                        color: sectionColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: collapsed ? 0 : 0.5,
                      duration: duration,
                      curve: InterGalacticMotion.standardOut,
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color: sectionColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 0, 0),
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: InterGalacticMotion.standardOut,
            switchOutCurve: InterGalacticMotion.standardIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: child,
                ),
              );
            },
            child: collapsed
                ? const SizedBox.shrink(key: ValueKey('favorites-collapsed'))
                : Column(
                    key: ValueKey('favorites-expanded:$id:${children.length}'),
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
          ),
        ),
      ],
    );
  }
}

class _FavoriteSpaceSectionHeader extends StatelessWidget {
  const _FavoriteSpaceSectionHeader({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FavoriteSpaceSectionRule(color: color, fadeToStart: true),
        ),
        Flexible(
          flex: 2,
          fit: FlexFit.loose,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: tiamat.Text.labelEmphasised(
                name,
                color: color,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softwrap: false,
              ),
            ),
          ),
        ),
        Expanded(
          child: _FavoriteSpaceSectionRule(color: color, fadeToStart: false),
        ),
      ],
    );
  }
}

class _FavoriteSpaceSectionRule extends StatelessWidget {
  const _FavoriteSpaceSectionRule({
    required this.color,
    required this.fadeToStart,
  });

  final Color color;
  final bool fadeToStart;

  @override
  Widget build(BuildContext context) {
    final colors = fadeToStart
        ? [color.withValues(alpha: 0), color]
        : [color, color.withValues(alpha: 0)];

    return SizedBox(
      height: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
      ),
    );
  }
}
