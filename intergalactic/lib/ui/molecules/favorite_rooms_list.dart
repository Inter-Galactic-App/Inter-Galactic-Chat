import 'dart:async';
import 'dart:ui';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/favorite_room_categories.dart';
import 'package:intergalactic/client/space_room_categories.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:intergalactic/ui/atoms/adaptive_context_menu.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/atoms/room_text_button.dart';
import 'package:intergalactic/ui/atoms/room_panel.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/pages/settings/favorites_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/favorites/settings_category_favorites.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/preference_image_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class FavoriteRoomsList extends StatefulWidget {
  const FavoriteRoomsList({
    super.key,
    required this.clientManager,
    this.filterClient,
    this.onRoomSelected,
    this.emptyMessage = "Star a room to add it to Favorites.",
    this.showHeader = false,
    this.header = "Favorites",
  });

  final ClientManager clientManager;
  final Client? filterClient;
  final Function(Room room, {bool bypassSpecialRoomType})? onRoomSelected;
  final String emptyMessage;
  final bool showHeader;
  final String header;

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
  SpaceRoomCategoryState favoriteCategoryState = SpaceRoomCategoryState.empty;
  bool favoriteCategoryStateLoaded = false;

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
            favoriteCategoryState = favoriteCategoryState.normalizedForRoomIds(
              favoriteRooms.map((room) => room.favoriteStorageId),
            );
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
      spaceRoomCategoryStore.onChanged
          .where((event) => event.spaceLocalId == favoriteRoomCategoriesLocalId)
          .listen(_onFavoriteCategoryStateChanged),
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

  List<Room> get favoriteRooms {
    final favoriteIds =
        reorderedFavoriteIds ?? preferences.getFavoriteRoomIds();
    final order = <String, int>{
      for (var i = 0; i < favoriteIds.length; i++) favoriteIds[i]: i,
    };

    final rooms = widget.clientManager.rooms.where((room) {
      if (widget.filterClient != null && room.client != widget.filterClient) {
        return false;
      }

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

  bool get _shouldUseFavoriteCategories =>
      favoriteCategoryStateLoaded && favoriteCategoryState.hasCategories;

  Future<void> _loadFavoriteCategoryState() async {
    final favoriteRoomIds = favoriteRooms
        .map((room) => room.favoriteStorageId)
        .toList(growable: false);
    final state = await loadFavoriteRoomCategoryState(
      favoriteRoomIds: favoriteRoomIds,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      favoriteCategoryState = state.normalizedForRoomIds(
        favoriteRooms.map((room) => room.favoriteStorageId),
      );
      favoriteCategoryStateLoaded = true;
    });
  }

  void _onFavoriteCategoryStateChanged(SpaceRoomCategoryChanged event) {
    if (!mounted) {
      return;
    }

    setState(() {
      favoriteCategoryState = event.state.normalizedForRoomIds(
        favoriteRooms.map((room) => room.favoriteStorageId),
      );
      favoriteCategoryStateLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = favoriteRooms;

    if (widget.showHeader) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final shouldUseSpaceSummary =
              constraints.maxWidth.isFinite &&
              constraints.maxWidth >= _spaceSummaryBreakpoint;

          if (shouldUseSpaceSummary) {
            return _buildSpaceSummarySurface(context, rooms);
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

  Widget _buildSpaceSummarySurface(BuildContext context, List<Room> rooms) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final countLabel = _roomCountLabel(rooms.length);

    return Column(
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
                            tiamat.Text.label('Favorites'),
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
          Positioned(
            top: 6,
            right: 6,
            child: _buildFavoritesSettingsButton(),
          ),
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

  Widget _buildSpaceSummaryBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bannerImage = _favoritesBannerImage();
    final iconImage = _favoritesIconImage();

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8),
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
    final bytes = decodePreferenceImageData(
      preferences.favoritesBannerImageData.value,
    );
    return bytes == null ? null : MemoryImage(bytes);
  }

  ImageProvider? _favoritesIconImage() {
    final bytes = decodePreferenceImageData(
      preferences.favoritesIconImageData.value,
    );
    return bytes == null ? null : MemoryImage(bytes);
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
              child: _buildSummaryFavoriteRoom(room),
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

  List<SpaceRoomCategoryGroup<Room>> _buildFavoriteCategoryGroups(
    List<Room> rooms,
  ) {
    return buildSpaceRoomCategoryGroups<Room>(
      state: favoriteCategoryState,
      rooms: rooms,
      roomId: (room) => room.favoriteStorageId,
      uncategorizedLabel: 'Uncategorized',
    );
  }

  String _categorySummaryLabel(SpaceRoomCategoryGroup<Room> group) {
    final count = group.rooms.length;
    return '${group.name}  ${count == 1 ? '1 room' : '$count rooms'}';
  }

  Future<void> _setFavoriteGroupCollapsed(
    SpaceRoomCategoryGroup<Room> group,
    bool collapsed,
  ) async {
    if (group.isUncategorized) {
      await spaceRoomCategoryStore.setUncategorizedCollapsed(
        favoriteRoomCategoriesLocalId,
        collapsed,
      );
      return;
    }

    await spaceRoomCategoryStore.setCategoryCollapsed(
      favoriteRoomCategoriesLocalId,
      group.id,
      collapsed,
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
    final updatedState = favoriteCategoryState.withExplicitRoomOrder(
      groupId,
      orderedRooms.map((room) => room.favoriteStorageId).toList(),
    );

    setState(() {
      favoriteCategoryState = updatedState;
    });
    await saveFavoriteRoomCategoryState(updatedState);
  }

  Widget _buildSummaryFavoriteRoom(Room room) {
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
          await preferences.setRoomFavorite(
            room.favoriteStorageId,
            false,
            legacyRoomId: room.localId,
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

    result = AdaptiveContextMenu(items: items, child: result);

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
      await preferences.setFavoriteRoomOrder(orderedIds);
      if (!mounted) {
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
    final titleColor = hasHeaderImage
        ? colorScheme.onSurface
        : colorScheme.onPrimary;

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
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: titleColor,
                        fontFamily: Layout.mobile ? "NunitoSans" : null,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                        shadows: !hasHeaderImage
                            ? null
                            : [
                                const BoxShadow(
                                  blurRadius: 2,
                                  spreadRadius: 10,
                                  color: Colors.black,
                                  offset: Offset(2, 2),
                                ),
                              ],
                      ),
                    ),
                  ),
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
