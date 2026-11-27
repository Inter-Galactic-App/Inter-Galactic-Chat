import 'dart:async'; // For StreamSubscription

import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/client/matrix/matrix_history_sharing.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart'; // For preferences
import 'package:intergalactic/ui/molecules/user_panel.dart';
import 'package:intergalactic/ui/atoms/room_download_status.dart';
import 'package:intergalactic/ui/atoms/stream_viewer_header_indicator.dart';
import 'package:intergalactic/utils/notification_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import '../../client/client.dart';

class RoomHeader extends StatefulWidget {
  const RoomHeader(
    this.room, {
    super.key,
    this.onTap,
    this.onBurgerMenuTap,
    this.menu,
    this.compact = false,
  });
  final Room room;
  final Widget? menu;
  final Function()? onTap;
  final bool compact;

  final void Function()? onBurgerMenuTap;
  @override
  State<RoomHeader> createState() => _RoomHeaderState();
}

class _RoomHeaderState extends State<RoomHeader> {
  late List<StreamSubscription> _subs;
  UserPresenceStatus? status;
  String? directMessagePartner;

  UserPresenceComponent? presence;

  @override
  void initState() {
    super.initState();

    final comp = widget.room.client.getComponent<DirectMessagesComponent>();
    bool isDm = comp?.isRoomDirectMessage(widget.room) == true;

    if (isDm) {
      status = UserPresenceStatus.unknown;
      presence = widget.room.client.getComponent<UserPresenceComponent>();
      directMessagePartner = comp!.getDirectMessagePartnerId(widget.room);
    }

    if (presence != null && directMessagePartner != null) {
      presence!.getUserPresence(directMessagePartner!).then((presence) {
        if (mounted) {
          setState(() {
            status = presence.status;
          });
        }
      });
    }

    _subs = [
      preferences.onSettingChanged.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
      widget.room.onUpdate.listen((_) {
        if (mounted) setState(() {});
      }),
      if (presence != null)
        presence!.onPresenceChanged.listen(onUserPresenceChanged),
    ];
  }

  @override
  void dispose() {
    for (var sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  void onUserPresenceChanged((String, UserPresence) event) {
    if (event.$1 == directMessagePartner) {
      setState(() {
        status = event.$2.status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    bool showRoomIcons = preferences.showRoomAvatars.value;
    bool useGenericIcons = preferences.usePlaceholderRoomAvatars.value;

    bool shouldShowDefaultIcon =
        (!showRoomIcons && !useGenericIcons) ||
        (showRoomIcons && !useGenericIcons && widget.room.avatar == null);
    IconData defaultIcon = widget.room.icon;
    final sharedEncryptedHistory =
        widget.room is MatrixRoom &&
        widget.room.isE2EE &&
        matrixHistoryVisibilityAllowsInviteSharing(
          (widget.room as MatrixRoom).matrixRoom.historyVisibility,
        );

    Widget iconWidget;

    var iconPadding = EdgeInsets.zero;

    if (shouldShowDefaultIcon) {
      iconPadding = EdgeInsets.fromLTRB(0, 0, 4, 0);
      iconWidget = Opacity(
        opacity: 0.5,
        child: m.Icon(
          defaultIcon,
          size: widget.compact && !Layout.mobile ? 16 : 20,
        ),
      );
    } else {
      iconPadding = EdgeInsets.fromLTRB(4, 0, 8, 0);
      iconWidget = tiamat.Avatar(
        radius: widget.compact && !Layout.mobile ? 11 : 15,
        image: showRoomIcons && widget.room.avatar != null
            ? widget.room.avatar
            : null,
        placeholderText:
            (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
                (!showRoomIcons && useGenericIcons)
            ? widget.room.displayName
            : "",
        placeholderColor:
            (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
                (!showRoomIcons && useGenericIcons)
            ? widget.room.defaultColor
            : m.Colors.grey,
      );
    }
    return HeaderView(
      showBurger: Layout.mobile,
      iconWidget: iconWidget,
      text: widget.room.displayName,
      iconPadding: iconPadding,
      topic: widget.room.topic,
      onTap: widget.onTap,
      onBurgerMenuTap: widget.onBurgerMenuTap,
      menu: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamViewerHeaderIndicator(
            room: widget.room,
            compact: widget.compact || Layout.mobile,
          ),
          if (widget.menu != null) widget.menu!,
        ],
      ),
      compact: widget.compact,
      sharedEncryptedHistory: sharedEncryptedHistory,
      activity: RoomDownloadStatus(room: widget.room),
      status: status,
    );
  }
}

class HeaderView extends StatelessWidget {
  const HeaderView({
    required this.text,
    this.iconWidget,
    this.iconPadding,
    this.onBurgerMenuTap,
    this.status,
    this.topic,
    this.menu,
    this.showBurger = true,
    this.onTap,
    this.compact = false,
    this.sharedEncryptedHistory = false,
    this.activity,
    super.key,
  });
  final void Function()? onTap;
  final void Function()? onBurgerMenuTap;
  final Widget? iconWidget;
  final UserPresenceStatus? status;
  final EdgeInsets? iconPadding;
  final String text;
  final String? topic;
  final bool showBurger;
  final Widget? menu;
  final bool compact;
  final bool sharedEncryptedHistory;
  final Widget? activity;

  @override
  Widget build(BuildContext context) {
    final isMobile = Layout.mobile;
    final compactDesktop = compact && !isMobile;

    final header = m.Material(
      color: m.Colors.transparent,
      child: m.InkWell(
        onTap: onTap,
        child: Container(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 14 : (compactDesktop ? 7 : 10),
              0,
              isMobile ? 14 : (compactDesktop ? 7 : 10),
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showBurger)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            0,
                            0,
                            isMobile ? 8 : 4,
                            0,
                          ),
                          child: HeaderBurger(
                            onTap: onBurgerMenuTap,
                            highlightColor: m.Colors.red.shade600,
                            notificationColor: m.Theme.of(
                              context,
                            ).colorScheme.onSurface,
                          ),
                        ),
                      if (iconWidget != null)
                        Padding(
                          padding:
                              iconPadding ??
                              EdgeInsets.fromLTRB(0, 0, isMobile ? 10 : 0, 0),
                          child: SizedBox(
                            child: Stack(
                              alignment: AlignmentGeometry.bottomRight,
                              children: [
                                iconWidget!,
                                if (status != null)
                                  UserPanelView.createPresenceIcon(
                                    context,
                                    status!,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Flexible(
                        child: ClipRect(
                          child: Row(
                            textBaseline: TextBaseline.ideographic,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              m.Text(
                                text,
                                style: m.Theme.of(context).textTheme.titleSmall!
                                    .copyWith(
                                      fontSize: isMobile
                                          ? 18
                                          : (compactDesktop ? 13 : null),
                                      fontWeight: isMobile
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: m.TextTheme.of(
                                        context,
                                      ).bodyMedium!.color,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (activity != null) activity!,
                              if (sharedEncryptedHistory && !compactDesktop)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    0,
                                    0,
                                    0,
                                  ),
                                  child: tiamat.Tooltip(
                                    text:
                                        'Encrypted full-history sharing is enabled for eligible invited devices.',
                                    child: m.Icon(
                                      m.Icons.history,
                                      size: 16,
                                      color: m.Theme.of(
                                        context,
                                      ).colorScheme.tertiary,
                                    ),
                                  ),
                                ),
                              if (!compactDesktop &&
                                  topic != null &&
                                  topic!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    0,
                                    8,
                                    0,
                                  ),
                                  child: tiamat.Text.labelLow("—"),
                                ),
                              if (!compactDesktop &&
                                  topic != null &&
                                  topic!.isNotEmpty)
                                Flexible(
                                  child: tiamat.Text.labelLow(
                                    topic!,
                                    color: isMobile
                                        ? m.Theme.of(
                                            context,
                                          ).colorScheme.secondary
                                        : null,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (menu != null) menu!,
              ],
            ),
          ),
        ),
      ),
    );

    if (!isMobile) {
      return header;
    }

    return header;
  }
}

class HeaderBurger extends StatefulWidget {
  const HeaderBurger({
    required this.highlightColor,
    required this.notificationColor,
    this.onTap,
    super.key,
  });
  final Function()? onTap;
  final Color highlightColor;
  final Color notificationColor;

  @override
  State<HeaderBurger> createState() => _HeaderBurgerState();
}

class _HeaderBurgerState extends State<HeaderBurger> {
  int highlightedNotificationCount = 0;
  int notificationCount = 0;
  late Color color;

  late List<StreamSubscription> subs;

  @override
  void initState() {
    super.initState();
    color = widget.notificationColor;
    subs = [
      clientManager!.directMessages.onHighlightedRoomsListUpdated.listen(
        (_) => updateState(),
      ),
      clientManager!.onSpaceUpdated.stream.listen((_) => updateState()),
    ];

    updateNotificationCount();
  }

  @override
  void dispose() {
    for (var sub in subs) sub.cancel();
    super.dispose();
  }

  void updateState() {
    setState(() {
      updateNotificationCount();
    });
  }

  void updateNotificationCount() {
    highlightedNotificationCount = 0;
    notificationCount = 0;

    var counts = NotificationUtils.getNotificationCounts();
    highlightedNotificationCount = counts.$1;
    notificationCount = counts.$2;

    if (notificationCount > 0) {
      color = widget.notificationColor;
    }

    if (highlightedNotificationCount > 0) {
      color = widget.highlightColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Layout.mobile;

    return SizedBox(
      width: isMobile ? 42 : 40,
      height: isMobile ? 42 : 40,
      child: Stack(
        alignment: AlignmentGeometry.xy(0.4, 0.3),
        children: [
          tiamat.IconButton(
            iconColor: m.ColorScheme.of(context).onSurface,
            icon: m.Icons.menu_rounded,
            size: 20,
            onPressed: widget.onTap,
          ),
          AnimatedScale(
            scale: highlightedNotificationCount + notificationCount > 0
                ? 1.0
                : 0.0,
            duration: m.Durations.medium4,
            curve: Curves.easeOutCubic,
            child: createNotificationIcon(context),
          ),
        ],
      ),
    );
  }

  Widget createNotificationIcon(BuildContext context) {
    var scheme = m.Theme.of(context).colorScheme;

    var backgroundColor = scheme.surfaceContainer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          width: 3,
          strokeAlign: BorderSide.strokeAlignOutside,
          color: backgroundColor,
        ),
      ),
      child: SizedBox(width: 8, height: 8),
    );
  }
}
