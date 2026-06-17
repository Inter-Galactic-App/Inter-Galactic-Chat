import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/ui/atoms/dot_indicator.dart';
import 'package:intergalactic/utils/scaled_app.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/tiamat.dart';
import '../atoms/space_icon.dart';

class SpaceSelector extends StatefulWidget {
  const SpaceSelector(this.spaces,
      {super.key,
      this.onSelected,
      this.onReordered,
      this.clearSelection,
      required this.width,
      this.shouldShowAvatarForSpace,
      this.header,
      this.footer});
  final List<Space> spaces;
  final double width;
  final Widget? header;
  final Widget? footer;
  final void Function(Space space)? onSelected;
  final void Function(List<Space> spaces)? onReordered;
  final void Function()? clearSelection;
  final bool Function(Space space)? shouldShowAvatarForSpace;

  static EdgeInsets get padding => const EdgeInsets.fromLTRB(7, 0, 7, 0);

  @override
  State<SpaceSelector> createState() => _SpaceSelectorState();
}

class _SpaceSelectorState extends State<SpaceSelector> {
  late List<Space> orderedSpaces;

  @override
  void initState() {
    super.initState();
    orderedSpaces = List<Space>.from(widget.spaces);
  }

  @override
  void didUpdateWidget(covariant SpaceSelector oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_haveSameSpaces(oldWidget.spaces, widget.spaces)) {
      orderedSpaces = List<Space>.from(widget.spaces);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Flexible(
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              physics:
                  BuildConfig.ANDROID ? const BouncingScrollPhysics() : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.header != null)
                      Padding(
                        padding: SpaceSelector.padding,
                        child: widget.header!,
                      ),
                    if (widget.header != null) const Seperator(),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.all(0),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: orderedSpaces.length,
                      onReorderStart: (_) => HapticFeedback.mediumImpact(),
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }

                        final item = orderedSpaces.removeAt(oldIndex);
                        orderedSpaces.insert(newIndex, item);

                        setState(() {});
                        widget.onReordered
                            ?.call(List<Space>.from(orderedSpaces));
                      },
                      itemBuilder: (context, index) {
                        final data = orderedSpaces[index];
                        final child = buildSpaceIcon(
                          space: data,
                          displayName: data.displayName,
                          onUpdate: data.onUpdate,
                          avatar: data.avatar,
                          notificationCount: data.displayNotificationCount,
                          highlightedNotificationCount:
                              data.displayHighlightedNotificationCount,
                          roomWideMentionNotification:
                              data.displayRoomWideMentionNotification,
                          userAvatar: data.client.self!.avatar,
                          userColor: data.client.self!.defaultColor,
                          userDisplayName: data.client.self!.displayName,
                          placeholderColor: data.color,
                        );

                        final key = ValueKey(data.localId);
                        if (BuildConfig.DESKTOP) {
                          return ReorderableDragStartListener(
                            key: key,
                            index: index,
                            child: child,
                          );
                        }

                        return ReorderableDelayedDragStartListener(
                          key: key,
                          index: index,
                          child: child,
                        );
                      },
                    ),
                    if (widget.footer != null)
                      Padding(
                        padding: SpaceSelector.padding,
                        child: widget.footer!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _haveSameSpaces(List<Space> a, List<Space> b) {
    if (a.length != b.length) {
      return false;
    }

    for (var i = 0; i < a.length; i++) {
      if (a[i].localId != b[i].localId) {
        return false;
      }
    }

    return true;
  }

  Widget buildSpaceIcon(
      {required String displayName,
      Stream<void>? onUpdate,
      ImageProvider? avatar,
      ImageProvider? userAvatar,
      Color? userColor,
      String? userDisplayName,
      Color? placeholderColor,
      int highlightedNotificationCount = 0,
      bool roomWideMentionNotification = false,
      int notificationCount = 0,
      required Space space}) {
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Padding(
          padding: SpaceSelector.padding,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
            child: SpaceIcon(
              displayName: displayName,
              onUpdate: onUpdate,
              avatar: avatar,
              userAvatar: userAvatar,
              spaceId: space.identifier,
              userColor: userColor,
              userDisplayName: userDisplayName,
              highlightedNotificationCount: highlightedNotificationCount,
              roomWideMentionNotification: roomWideMentionNotification,
              notificationCount: notificationCount,
              width: widget.width,
              placeholderColor: placeholderColor,
              onTap: () {
                widget.onSelected?.call(space);
              },
              showUser: widget.shouldShowAvatarForSpace?.call(space) ?? false,
            ),
          ),
        ),
        if (notificationCount > 0) messageOverlay()
      ],
    );
  }

  Widget messageOverlay() {
    return const Positioned(left: -6, child: DotIndicator());
  }
}
