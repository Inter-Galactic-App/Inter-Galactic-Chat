import 'dart:async';

import 'package:intergalactic/client/space.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/atoms/notification_badge.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';

class SpaceIcon extends StatefulWidget {
  const SpaceIcon(
      {super.key,
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
      this.userColor});
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

    spaceSelectionSub =
        EventBus.onSelectedSpaceChanged.stream.listen(onSelectedSpaceChanged);

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
    Widget icon = ImageButton(
      border: selected
          ? Border.all(
              color: ColorScheme.of(context).inverseSurface,
              width: 3,
              strokeAlign: 0.5)
          : null,
      image: widget.avatar,
      onTap: widget.onTap,
      size: widget.width,
      placeholderColor: widget.placeholderColor,
      placeholderText: widget.displayName,
    );

    if (Layout.mobile) {
      final radius = BorderRadius.circular(widget.width * 0.34);
      icon = MobileGlassEdgeHighlight(
        borderRadius: radius,
        style: MobileGlassHighlightStyle.composer,
        intensity: 0.3,
        highlighted: selected,
        child: icon,
      );
    }

    return Stack(children: [
      SideNavigationBar.tooltip(widget.displayName, icon, context),
      if (widget.showUser) avatarOverlay(),
      if (widget.roomWideMentionNotification ||
          widget.highlightedNotificationCount > 0)
        notificationOverlay(),
    ]);
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
                boxShadow: const [
                  BoxShadow(color: Colors.black, blurRadius: 4)
                ],
              ),
              child: Avatar(
                radius: 10,
                image: widget.userAvatar,
                placeholderColor: widget.userColor,
                placeholderText: widget.userDisplayName,
              )),
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
              borderRadius: BorderRadius.circular(5)),
        ),
      ),
    );
  }
}
