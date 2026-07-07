import 'dart:async';

import 'package:intergalactic/client/components/calendar_room/calendar_room_component.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:intergalactic/ui/atoms/adaptive_context_menu.dart';
import 'package:intergalactic/ui/atoms/dot_indicator.dart';
import 'package:intergalactic/ui/atoms/notification_badge.dart';
import 'package:intergalactic/ui/atoms/tiny_pill.dart';
import 'package:intergalactic/ui/molecules/dm_pin_dialog.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:commet_calendar_widget/calendar.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomTextButton extends StatefulWidget {
  const RoomTextButton(
    this.room, {
    this.highlight = false,
    this.trailingIndicatorInset = 0,
    this.onTap,
    super.key,
  });
  final bool highlight;
  final double trailingIndicatorInset;
  final Room room;
  final Function(Room room, {bool bypassSpecialRoomType})? onTap;

  @override
  State<RoomTextButton> createState() => _RoomTextButtonState();
}

class _RoomTextButtonState extends State<RoomTextButton> {
  late List<StreamSubscription> subs;
  VoipRoomComponent? voipRoom;
  CalendarRoom? calendarRoom;
  List<String>? voipRoomParticipants;
  List<MatrixCalendarEventState>? calendarEvents;

  bool get isFavorite => preferences.isRoomFavorite(
    widget.room.favoriteStorageId,
    legacyRoomId: widget.room.localId,
  );
  bool get isDirectMessage =>
      widget.room.client
          .getComponent<DirectMessagesComponent>()
          ?.isRoomDirectMessage(widget.room) ==
      true;
  bool get isLocked => dmLockController.isRoomLocked(widget.room);

  @override
  void initState() {
    voipRoom = widget.room.getComponent<VoipRoomComponent>();
    calendarRoom = widget.room.getComponent<CalendarRoom>();

    subs = [
      widget.room.onUpdate.listen(onRoomUpdate),
      preferences.onSettingChanged.listen(onRoomUpdate),
      if (voipRoom != null)
        voipRoom!.onParticipantsChanged.listen(onVoipParticipantsChanged),
      if (calendarRoom != null)
        calendarRoom!.onEventsChanged.listen(onCalendarEventsChanged),
    ];

    if (voipRoom != null) {
      voipRoomParticipants = voipRoom?.getCurrentParticipants();
    }

    if (calendarRoom?.calendar != null) {
      onCalendarEventsChanged(());
    }

    if (voipRoomParticipants?.isNotEmpty == true) {
      for (var participant in voipRoomParticipants!) {
        widget.room.fetchMember(participant).then((_) {
          if (mounted) {
            setState(() {});
          }
        });
      }
    }

    super.initState();
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  void onCalendarEventsChanged(void event) {
    if (!mounted) {
      return;
    }

    setState(() {
      calendarEvents = calendarRoom!
          .getEventsOnDay(DateTime.now())
          .where((i) => i.isUnavailability == false)
          .toList();
    });
  }

  void onRoomUpdate([dynamic _]) {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  static const double height = 37;

  @override
  Widget build(BuildContext context) {
    IconData defaultIcon = widget.room.icon;

    final colorScheme = Theme.of(context).colorScheme;
    final roomWideMentionColor = colorScheme.tertiary;
    var color = colorScheme.secondary;
    final hasRoomWideMention = widget.room.displayRoomWideMentionNotification;

    if (widget.room.notificationCount > 0 ||
        widget.room.highlightedNotificationCount > 0 ||
        widget.highlight) {
      color = colorScheme.onSurface;
    }

    if (hasRoomWideMention) {
      color = roomWideMentionColor;
    }

    bool showRoomIcons = preferences.showRoomAvatars.value;
    bool useGenericIcons = preferences.usePlaceholderRoomAvatars.value;

    bool shouldShowDefaultIcon =
        (!showRoomIcons && !useGenericIcons) ||
        (showRoomIcons && !useGenericIcons && widget.room.avatar == null);

    String displayName = widget.room.displayName;

    Color? avatarPlaceholderColor =
        (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
            (!showRoomIcons && useGenericIcons)
        ? widget.room.defaultColor
        : null;

    String? avatarPlaceholderText =
        (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
            (!showRoomIcons && useGenericIcons)
        ? widget.room.displayName
        : null;

    bool startsWithEmoji = TextUtils.isEmoji(
      widget.room.displayName.characters.first,
    );

    if (startsWithEmoji && widget.room.avatar == null) {
      shouldShowDefaultIcon = false;
      var emoji = displayName.characters.first;
      displayName = displayName.characters.skip(1).string.trim();
      avatarPlaceholderColor = Colors.transparent;
      avatarPlaceholderText = emoji;
    }
    var customBuilder = null;

    if (voipRoomParticipants?.isNotEmpty == true) {
      customBuilder = buildCallParticipants;
    }

    if (calendarEvents?.isNotEmpty == true) {
      customBuilder = buildEvents;
    }

    Widget result = SizedBox(
      height: customBuilder == null ? height : null,
      child: tiamat.TextButton(
        displayName,
        customBuilder: customBuilder,
        highlighted: widget.highlight,
        icon: shouldShowDefaultIcon ? defaultIcon : null,
        avatar: showRoomIcons && widget.room.avatar != null
            ? widget.room.avatar
            : null,
        avatarRadius: 12,
        avatarPlaceholderColor: avatarPlaceholderColor,
        avatarPlaceholderText: avatarPlaceholderText,
        iconColor: color,
        textColor: color,
        softwrap: false,
        onTap: () => widget.onTap?.call(widget.room),
        footer: buildFooter(),
      ),
    );

    if (hasRoomWideMention) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          color: roomWideMentionColor.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: roomWideMentionColor.withValues(alpha: 0.5),
          ),
        ),
        child: result,
      );
    }

    result = AccessibleInteractiveRegion(
      semanticLabel: _semanticLabel(),
      semanticHint: "Open room",
      selected: widget.highlight,
      onActivate: widget.onTap == null
          ? null
          : () => widget.onTap?.call(widget.room),
      borderRadius: BorderRadius.circular(8),
      child: result,
    );

    var items = [
      ContextMenuItem(
        text: "Mark as Read",
        icon: Icons.visibility,
        onPressed: () => widget.room.markAsRead(),
      ),
      if (isDirectMessage)
        ContextMenuItem(
          text: isLocked ? "Unlock DM" : "Lock DM",
          icon: isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
          onPressed: () => _toggleRoomLock(!isLocked),
        ),
      ContextMenuItem(
        text: isFavorite ? "Remove from Favorites" : "Add to Favorites",
        icon: isFavorite ? Icons.star_outline : Icons.star,
        onPressed: () async {
          await preferences.setRoomFavorite(
            widget.room.favoriteStorageId,
            !isFavorite,
            legacyRoomId: widget.room.localId,
          );
          if (mounted) {
            setState(() {});
          }
        },
      ),
      if (widget.room.isSpecialRoomType)
        ContextMenuItem(
          text: "Open as Text Chat",
          icon: Icons.tag,
          onPressed: () =>
              widget.onTap?.call(widget.room, bypassSpecialRoomType: true),
        ),
      if (voipRoom != null && preferences.developerMode.value)
        ContextMenuItem(
          text: "Clear Membership Status",
          icon: Icons.call_end,
          onPressed: () => voipRoom?.clearAllCallMembershipStatus(),
        ),
    ];

    result = AdaptiveContextMenu(items: items, child: result);

    return result;
  }

  String _semanticLabel() {
    final parts = <String>[widget.room.displayName];

    if (widget.room.displayRoomWideMentionNotification) {
      parts.add("room-wide mention");
    } else if (widget.room.displayHighlightedNotificationCount > 0) {
      parts.add("${widget.room.displayHighlightedNotificationCount} mention");
    } else if (widget.room.displayNotificationCount > 0) {
      parts.add("unread messages");
    }

    if (isFavorite) {
      parts.add("favorite");
    }

    if (isDirectMessage && isLocked) {
      parts.add(
        dmLockController.isRoomUnlocked(widget.room)
            ? "direct message unlocked"
            : "direct message locked",
      );
    }

    return parts.join(", ");
  }

  Widget? buildFooter() {
    final List<Widget> items = [];

    if (isFavorite) {
      items.add(
        Icon(
          Icons.star,
          size: 14,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    if (isDirectMessage && isLocked) {
      items.add(
        Icon(
          dmLockController.isRoomUnlocked(widget.room)
              ? Icons.lock_open_rounded
              : Icons.lock_rounded,
          size: 14,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    if (widget.room.displayRoomWideMentionNotification) {
      items.add(
        NotificationBadge(
          widget.room.displayHighlightedNotificationCount,
          exclamation: true,
          tone: NotificationBadgeTone.warning,
        ),
      );
    } else if (widget.room.displayHighlightedNotificationCount > 0) {
      items.add(
        NotificationBadge(
          widget.room.displayHighlightedNotificationCount,
          tone: NotificationBadgeTone.danger,
        ),
      );
    } else if (widget.room.displayNotificationCount > 0) {
      items.add(
        const Padding(padding: EdgeInsets.all(2.0), child: DotIndicator()),
      );
    }

    if (items.isEmpty) {
      return null;
    }

    final Widget footer = items.length == 1
        ? items.first
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                items[i],
              ],
            ],
          );

    if (widget.trailingIndicatorInset <= 0) {
      return footer;
    }

    return Padding(
      padding: EdgeInsets.only(right: widget.trailingIndicatorInset),
      child: footer,
    );
  }

  Widget buildCallParticipants(Widget child, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: height, child: child),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 0, 4),
          child: Column(
            children: [
              for (var participant in voipRoomParticipants!)
                buildCallMember(participant),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildEvents(Widget child, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: height, child: child),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 0, 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceDim.withAlpha(180),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  tiamat.Text.labelLow("Today: "),
                  for (var event in calendarEvents!) buildEvent(event),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildCallMember(String identifier) {
    var color = Theme.of(context).colorScheme.secondary;

    final member = voipRoom?.room.getMemberOrFallback(identifier);
    if (member == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: height,
      child: tiamat.TextButton(
        member.displayName,
        textColor: color,
        avatar: member.avatar,
        avatarPlaceholderColor: member.defaultColor,
        avatarPlaceholderText: member.displayName,
      ),
    );
  }

  Widget buildEvent(MatrixCalendarEventState event) {
    final senderId = event.senderId;
    if (senderId == null) {
      return const SizedBox.shrink();
    }

    var color = calendarRoom!.calendar!.config.getColorFromUser(senderId);

    return TinyPill(
      event.data.title,
      background: calendarRoom!.calendar!.config.processEventColor(
        color,
        context,
      ),
      foreground: calendarRoom!.calendar!.config.processEventTextColor(
        color,
        context,
      ),
    );
  }

  void onVoipParticipantsChanged(void event) {
    if (!mounted) {
      return;
    }

    setState(() {
      voipRoomParticipants = voipRoom?.getCurrentParticipants();
    });
  }

  Future<void> _toggleRoomLock(bool shouldLock) async {
    if (!shouldLock) {
      await dmLockController.setRoomLocked(widget.room, false);
      return;
    }

    if (!dmLockController.isPinConfiguredForClient(widget.room.client)) {
      final result = await AdaptiveDialog.show<DmPinDialogResult>(
        context,
        title: "Set PIN",
        builder: (_) => const DmPinDialog(
          mode: DmPinDialogMode.setPin,
          description:
              "Set a local PIN before locking direct messages on this account.",
          submitLabel: "Save PIN",
        ),
      );

      final newPin = result?.newPin;
      if (newPin == null || newPin.isEmpty) {
        return;
      }

      await dmLockController.setPinForClient(widget.room.client, newPin);
    }

    await dmLockController.setRoomLocked(widget.room, true);
  }
}
