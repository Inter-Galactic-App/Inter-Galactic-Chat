import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/room_preview.dart';
import 'package:intergalactic/client/space_child.dart';
import 'package:intergalactic/client/space_room_categories.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:intergalactic/ui/atoms/adaptive_context_menu.dart';
import 'package:intergalactic/ui/atoms/room_preview_text_button.dart';
import 'package:intergalactic/ui/atoms/room_text_button.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceList extends StatefulWidget {
  const SpaceList(this.space,
      {this.onRoomSelected,
      this.isTopLevel = true,
      this.currentDepth = 0,
      this.maxDepth = 5,
      this.roomIndicatorTrailingInset = 0,
      super.key});
  final Function(Room room, {bool bypassSpecialRoomType})? onRoomSelected;

  final bool isTopLevel;

  final Space space;

  final int maxDepth;

  final int currentDepth;

  final double roomIndicatorTrailingInset;

  @override
  State<SpaceList> createState() => _SpaceListState();
}

class _SpaceListState extends State<SpaceList> {
  late List<RoomPreview> previews;

  late List<SpaceChild> children;

  late List<StreamSubscription> subs;

  SpaceRoomCategoryState categoryState = SpaceRoomCategoryState.empty;
  bool categoryStateLoaded = false;

  Room? selectedRoom;
  String get labelRoomsList => Intl.message("Rooms",
      desc: "Header label for the list of rooms", name: "labelRoomsList");
  String joinRoomConfirmationPrompt(String roomName) => Intl.message(
        "Are you sure you want to join the room '$roomName'?",
        desc: "Confirmation prompt before joining a room from a space preview",
        name: "joinRoomConfirmationPrompt",
        args: [roomName],
      );
  String knockRoomConfirmationPrompt(String roomName) => Intl.message(
        "Request to join '$roomName'? An admin will need to approve the knock.",
        desc:
            "Confirmation prompt before requesting access to a knock-only room",
        name: "knockRoomConfirmationPrompt",
        args: [roomName],
      );
  String get knockRequestedFeedback => Intl.message(
        "Knock sent. An admin can approve your access.",
        desc: "Feedback shown after requesting access to a knock-only room",
        name: "knockRequestedFeedback",
      );

  @override
  void initState() {
    children = applySavedChildOrder(widget.space.children);
    previews = widget.space.childPreviews;

    subs = [
      widget.space.onChildRoomPreviewAdded
          .listen((_) => onPreviewListChanged()),
      widget.space.onChildRoomPreviewsUpdated
          .listen((_) => onPreviewListChanged()),
      widget.space.onChildRoomPreviewRemoved
          .listen((_) => onPreviewListChanged()),
      EventBus.onSelectedRoomChanged.stream.listen(onRoomSelected),
      widget.space.onUpdate.listen(onSpaceUpdated),
      widget.space.onChildSpaceAdded.listen(onSpaceUpdated),
      widget.space.onChildSpaceRemoved.listen(onSpaceUpdated),
      widget.space.onRoomAdded.listen(onRoomUpdated),
      widget.space.onRoomRemoved.listen(onRoomUpdated),
      for (var room in widget.space.rooms) room.onUpdate.listen(onRoomUpdated),
      preferences.onSettingChanged.listen((_) => onPreferencesChanged()),
      spaceRoomCategoryStore.onChanged
          .where((event) => event.spaceLocalId == widget.space.localId)
          .listen(onCategoryStateChanged),
    ];

    loadCategoryState();
    super.initState();
  }

  Future<void> loadCategoryState() async {
    final state = await spaceRoomCategoryStore.loadForSpace(widget.space);
    if (!mounted) {
      return;
    }

    setState(() {
      categoryState = state.normalizedForRoomIds(
        widget.space.rooms.map((room) => room.identifier),
      );
      categoryStateLoaded = true;
    });
  }

  void onCategoryStateChanged(SpaceRoomCategoryChanged event) {
    if (!mounted) {
      return;
    }

    setState(() {
      categoryState = event.state.normalizedForRoomIds(
        widget.space.rooms.map((room) => room.identifier),
      );
      categoryStateLoaded = true;
    });
  }

  void onPreviewListChanged() {
    setState(() {
      previews = widget.space.childPreviews;
    });
  }

  void onSpaceUpdated(void event) {
    setState(() {
      children = applySavedChildOrder(widget.space.children);
      previews = widget.space.childPreviews;
    });
    unawaited(loadCategoryState());
  }

  void onRoomUpdated(void event) {
    setState(() {
      children = applySavedChildOrder(widget.space.children);
      categoryState = categoryState.normalizedForRoomIds(
        widget.space.rooms.map((room) => room.identifier),
      );
    });
  }

  void onPreferencesChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      children = applySavedChildOrder(widget.space.children);
    });
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  void onRoomSelected(Room? event) {
    if (mounted)
      setState(() {
        selectedRoom = event;
      });
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final child = children.removeAt(oldIndex);
    children.insert(newIndex, child);
    setState(() {});
    preferences.setSpaceChildOrder(
      widget.space.localId,
      children.map((child) => child.id).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (categoryStateLoaded && categoryState.hasCategories) {
      return buildCategorizedList();
    }

    final reorderableItems = [
      for (int index = 0; index < children.length; index++)
        ReorderableDelayedDragStartListener(
          key: ValueKey("${widget.space.localId}:${children[index].id}"),
          index: index,
          child: buildChild(children[index]),
        ),
    ];

    if (widget.isTopLevel) {
      // Top-level: owns its own scroll so drag reorder isn't stolen by a
      // parent SingleChildScrollView.
      Widget? footer;
      if (preferences.showRoomPreviewsInSpaceSidebar.value &&
          previews.isNotEmpty) {
        footer = Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (var preview in previews) buildPreviewChild(preview)],
        );
      }

      return ReorderableListView(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.all(0),
        onReorderStart: (_) => HapticFeedback.mediumImpact(),
        onReorder: _onReorder,
        footer: footer,
        children: reorderableItems,
      );
    }

    // Nested (inside a TextButtonExpander): keep shrink-wrap so the parent
    // scroll view sizes it correctly.
    return Column(
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(0),
          onReorderStart: (_) => HapticFeedback.mediumImpact(),
          itemCount: children.length,
          itemBuilder: (context, index) {
            final child = children[index];
            final item = buildChild(child);
            final key = ValueKey("${widget.space.localId}:${child.id}");
            return ReorderableDelayedDragStartListener(
              key: key,
              index: index,
              child: item,
            );
          },
          onReorder: _onReorder,
        ),
        if (preferences.showRoomPreviewsInSpaceSidebar.value)
          for (var preview in previews) buildPreviewChild(preview),
      ],
    );
  }

  Widget buildCategorizedList() {
    final items = buildCategorizedItems();
    final previewItems = preferences.showRoomPreviewsInSpaceSidebar.value
        ? [for (var preview in previews) buildPreviewChild(preview)]
        : const <Widget>[];

    if (widget.isTopLevel) {
      return ListView(
        padding: const EdgeInsets.all(0),
        children: [
          ...items,
          ...previewItems,
        ],
      );
    }

    return Column(
      children: [
        ...items,
        ...previewItems,
      ],
    );
  }

  List<Widget> buildCategorizedItems() {
    final roomChildren = <SpaceChildRoom>[];
    final otherChildren = <SpaceChild>[];

    for (final child in children) {
      if (child is SpaceChildRoom) {
        roomChildren.add(child);
      } else {
        otherChildren.add(child);
      }
    }

    final groups = buildSpaceRoomCategoryGroups<SpaceChildRoom>(
      state: categoryState,
      rooms: roomChildren,
      roomId: (child) => child.child.identifier,
      uncategorizedLabel: 'Uncategorized',
    );

    return [
      for (final group in groups) buildCategoryGroup(group),
      for (final child in otherChildren) buildChild(child),
    ];
  }

  Widget buildCategoryGroup(SpaceRoomCategoryGroup<SpaceChildRoom> group) {
    return _SpaceCategoryExpander(
      id: group.id,
      name: group.name,
      collapsed: group.collapsed,
      onCollapsedChanged: (collapsed) {
        if (group.isUncategorized) {
          unawaited(
            spaceRoomCategoryStore.setUncategorizedCollapsedForSpace(
              widget.space,
              collapsed,
            ),
          );
          return;
        }

        unawaited(
          spaceRoomCategoryStore.setCategoryCollapsedForSpace(
            widget.space,
            group.id,
            collapsed,
          ),
        );
      },
      children: [
        for (final child in group.rooms)
          RoomTextButton(
            child.child,
            onTap: widget.onRoomSelected,
            highlight: selectedRoom == child.child,
            trailingIndicatorInset: widget.roomIndicatorTrailingInset,
          ),
      ],
    );
  }

  List<SpaceChild> applySavedChildOrder(List<SpaceChild> items) {
    final savedOrder = preferences.getSpaceChildOrder(widget.space.localId);
    if (savedOrder.isEmpty) {
      return List<SpaceChild>.from(items);
    }

    final itemMap = <String, SpaceChild>{
      for (final item in items) item.id: item,
    };

    final ordered = <SpaceChild>[];
    for (final id in savedOrder) {
      final item = itemMap.remove(id);
      if (item != null) {
        ordered.add(item);
      }
    }

    for (final item in items) {
      if (itemMap.containsKey(item.id)) {
        ordered.add(item);
      }
    }

    return ordered;
  }

  Widget roomsList() {
    if (widget.isTopLevel) {
      return tiamat.TextButtonExpander(labelRoomsList,
          childrenPadding: const EdgeInsets.fromLTRB(2, 0, 0, 0),
          initiallyExpanded: true,
          iconColor: Theme.of(context).colorScheme.secondary,
          textColor: Theme.of(context).colorScheme.secondary,
          children: [buildRoomsList()]);
    } else {
      return buildRoomsList();
    }
  }

  Widget buildRoomsList() {
    return ImplicitlyAnimatedList(
      itemData: widget.space.rooms,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(0),
      initialAnimation: false,
      itemBuilder: (context, data) {
        return RoomTextButton(
          data,
          onTap: widget.onRoomSelected,
          highlight: selectedRoom == data,
          trailingIndicatorInset: widget.roomIndicatorTrailingInset,
        );
      },
    );
  }

  Widget buildPreviewChild(RoomPreview preview) {
    return RoomPreviewTextButton(
      preview,
      onTap: joinRoomWithConfirmation,
    );
  }

  Future<void> joinRoomWithConfirmation(RoomPreview preview) async {
    final requiresKnock = _previewRequiresKnock(preview);
    final prompt = requiresKnock
        ? knockRoomConfirmationPrompt(preview.displayName)
        : joinRoomConfirmationPrompt(preview.displayName);
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      prompt: prompt,
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final result = await widget.space.client.joinRoomFromPreview(preview);
      if (!mounted) {
        return;
      }
      switch (result.outcome) {
        case RoomPreviewJoinOutcome.joined:
          final room = result.room;
          if (room == null) {
            return;
          }
          await widget.onRoomSelected?.call(room);
          if (!mounted) {
            return;
          }
          subs.add(room.onUpdate.listen(onRoomUpdated));
          break;
        case RoomPreviewJoinOutcome.knockRequested:
          _showJoinFeedback(knockRequestedFeedback);
          break;
      }
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      await AdaptiveDialog.showError(context, error, stackTrace);
    }
  }

  bool _previewRequiresKnock(RoomPreview preview) {
    final visibility = preview.visibility;
    return visibility is RoomVisibilityKnock ||
        visibility is RoomVisibilityKnockRestricted;
  }

  void _showJoinFeedback(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget buildChild(SpaceChild child) {
    if (child case SpaceChildSpace _) {
      if (widget.currentDepth < widget.maxDepth) {
        return AdaptiveContextMenu(
          items: [
            if (widget.space.permissions.canEditChildren)
              tiamat.ContextMenuItem(
                icon: Icons.remove_circle,
                text: "Remove from ${widget.space.displayName}",
                onPressed: () async {
                  if (await AdaptiveDialog.confirmation(context) == true) {
                    widget.space.removeChild(child);
                  }
                },
              )
          ],
          child: tiamat.TextButtonExpander(child.child.displayName,
              initiallyExpanded: true,
              childrenPadding: const EdgeInsets.fromLTRB(2, 0, 0, 0),
              iconColor: Theme.of(context).colorScheme.secondary,
              textColor: Theme.of(context).colorScheme.secondary,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: SpaceList(
                    child.child,
                    isTopLevel: false,
                    currentDepth: widget.currentDepth + 1,
                    onRoomSelected: widget.onRoomSelected,
                    roomIndicatorTrailingInset:
                        widget.roomIndicatorTrailingInset,
                  ),
                )
              ]),
        );
      } else {
        return tiamat.TextButton(widget.space.displayName);
      }
    }

    if (child case SpaceChildRoom _)
      return RoomTextButton(
        child.child,
        onTap: widget.onRoomSelected,
        highlight: selectedRoom == child.child,
        trailingIndicatorInset: widget.roomIndicatorTrailingInset,
      );

    return Container();
  }
}

class _SpaceCategoryExpander extends StatelessWidget {
  const _SpaceCategoryExpander({
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
    final categoryColor = _normalRoomListNameColor(theme);
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
          semanticHint:
              collapsed ? 'Expand space category' : 'Collapse space category',
          semanticOnTapHint:
              collapsed ? 'Expand category' : 'Collapse category',
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
                      child: _SpaceCategoryHeader(
                        name: name,
                        color: categoryColor,
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
                        color: categoryColor,
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
                ? const SizedBox.shrink(key: ValueKey('collapsed'))
                : Column(
                    key: ValueKey('expanded:$id:${children.length}'),
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
          ),
        ),
      ],
    );
  }
}

Color _normalRoomListNameColor(ThemeData theme) {
  return theme.colorScheme.secondary;
}

class _SpaceCategoryHeader extends StatelessWidget {
  const _SpaceCategoryHeader({
    required this.name,
    required this.color,
  });

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SpaceCategoryRule(
            color: color,
            fadeToStart: true,
          ),
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
          child: _SpaceCategoryRule(
            color: color,
            fadeToStart: false,
          ),
        ),
      ],
    );
  }
}

class _SpaceCategoryRule extends StatelessWidget {
  const _SpaceCategoryRule({
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
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
        ),
      ),
    );
  }
}
