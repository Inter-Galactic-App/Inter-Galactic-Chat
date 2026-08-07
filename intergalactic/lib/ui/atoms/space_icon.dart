import 'dart:async';

import 'package:intergalactic/client/space.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:intergalactic/ui/atoms/notification_badge.dart';
import 'package:intergalactic/ui/atoms/persistent_rail_icon_row.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' show Avatar, ImageButton;

class SpaceIcon extends StatefulWidget {
  const SpaceIcon({
    super.key,
    this.width = 44,
    this.onTap,
    this.showUser = false,
    this.onUpdate,
    required this.spaceId,
    this.avatar,
    this.placeholderColor,
    this.notificationCount = 0,
    this.highlightedNotificationCount = 0,
    this.roomWideMentionNotification = false,
    required this.displayName,
    this.userAvatar,
    this.userDisplayName,
    this.userColor,
  });
  final double width;
  final void Function()? onTap;
  final bool showUser;
  final String spaceId;
  final Stream<void>? onUpdate;
  final String displayName;
  final Color? placeholderColor;
  final int notificationCount;
  final int highlightedNotificationCount;
  final bool roomWideMentionNotification;
  final ImageProvider? avatar;
  final ImageProvider? userAvatar;
  final String? userDisplayName;
  final Color? userColor;

  @override
  State<SpaceIcon> createState() => _SpaceIconState();
}

class _SpaceIconState extends State<SpaceIcon> {
  StreamSubscription? subscription;
  StreamSubscription? spaceSelectionSub;
  @override
  void initState() {
    subscription = widget.onUpdate?.listen((event) {
      setState(() {});
    });

    spaceSelectionSub = EventBus.onSelectedSpaceChanged.stream.listen(
      onSelectedSpaceChanged,
    );

    super.initState();
  }

  bool selected = false;

  void onSelectedSpaceChanged(Space? event) {
    setState(() {
      selected = event?.identifier == widget.spaceId;
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    spaceSelectionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showPersistentLabel = shouldShowPersistentRailIconLabel(context);
    final iconSize = persistentRailIconSizeFor(
      baseSize: widget.width,
      showPersistentLabel: showPersistentLabel,
    );
    final radius = BorderRadius.circular(iconSize * 0.34);
    Widget icon = ImageButton(
      key: ValueKey<int>(
        Object.hash('space-icon-avatar', widget.spaceId, widget.avatar),
      ),
      border: selected && !showPersistentLabel
          ? Border.all(
              color: ColorScheme.of(context).inverseSurface,
              width: 3,
              strokeAlign: 0.5,
            )
          : null,
      image: widget.avatar,
      onTap: showPersistentLabel ? null : widget.onTap,
      size: iconSize,
      placeholderColor: widget.placeholderColor,
      placeholderText: widget.displayName,
    );

    if (Layout.mobile) {
      icon = MobileGlassEdgeHighlight(
        borderRadius: radius,
        style: MobileGlassHighlightStyle.composer,
        intensity: 0.3,
        highlighted: selected,
        child: icon,
      );
    }

    final hint = selected ? "Selected space" : "Open space";
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        if (widget.showUser) avatarOverlay(),
        if (widget.roomWideMentionNotification ||
            widget.highlightedNotificationCount > 0)
          notificationOverlay(),
      ],
    );
    final child = showPersistentLabel
        ? PersistentRailIconRow(
            icon: content,
            iconSize: iconSize,
            label: widget.displayName,
            selected: selected,
          )
        : content;
    final regionRadius = showPersistentLabel
        ? const BorderRadius.all(Radius.circular(8))
        : radius;

    return SideNavigationBar.tooltip(
      widget.displayName,
      AccessibleInteractiveRegion(
        semanticLabel: widget.displayName,
        semanticHint: hint,
        selected: selected,
        onActivate: widget.onTap,
        borderRadius: regionRadius,
        excludeChildSemantics: true,
        persistentLabel: showPersistentLabel ? null : widget.displayName,
        persistentLabelMaxWidth: widget.width,
        child: child,
      ),
      context,
    );
  }

  Positioned avatarOverlay() {
    return Positioned(
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: 20,
          height: 20,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 4)],
            ),
            child: Avatar(
              key: ValueKey<int>(
                Object.hash(
                  'space-icon-user-avatar',
                  widget.spaceId,
                  widget.userDisplayName,
                  widget.userAvatar,
                ),
              ),
              radius: 10,
              image: widget.userAvatar,
              placeholderColor: widget.userColor,
              placeholderText: widget.userDisplayName,
            ),
          ),
        ),
      ),
    );
  }

  Positioned notificationOverlay() {
    return Positioned(
      right: 0,
      top: 0,
      child: SizedBox(
        width: 20,
        height: 20,
        child: NotificationBadge(
          widget.highlightedNotificationCount,
          exclamation: widget.roomWideMentionNotification,
          tone: widget.roomWideMentionNotification
              ? NotificationBadgeTone.warning
              : NotificationBadgeTone.danger,
        ),
      ),
    );
  }

  Positioned messageOverlay() {
    return Positioned(
      left: 0,
      child: SizedBox(
        width: 8,
        height: 8,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }
}
