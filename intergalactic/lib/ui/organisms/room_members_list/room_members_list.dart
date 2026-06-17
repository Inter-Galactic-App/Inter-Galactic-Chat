import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/space.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/molecules/user_list.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/settings_category_room.dart';
import 'package:intergalactic/ui/pages/settings/room_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomMembersListWidget extends StatefulWidget {
  const RoomMembersListWidget(
    this.room, {
    this.compact = false,
    this.contextSpace,
    this.forceNicknamesButton = false,
    this.onNicknamesPressed,
    super.key,
  });
  final Room room;
  final bool compact;
  final Space? contextSpace;
  final bool forceNicknamesButton;
  final VoidCallback? onNicknamesPressed;

  @override
  State<RoomMembersListWidget> createState() => _RoomMembersListWidgetState();
}

class _RoomMembersListWidgetState extends State<RoomMembersListWidget> {
  late bool isDirectMessage;
  @override
  void initState() {
    isDirectMessage = _computeIsDirectMessage();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant RoomMembersListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room == widget.room) {
      return;
    }

    final nextIsDirectMessage = _computeIsDirectMessage();
    if (nextIsDirectMessage != isDirectMessage) {
      setState(() {
        isDirectMessage = nextIsDirectMessage;
      });
    } else {
      isDirectMessage = nextIsDirectMessage;
    }
  }

  bool _computeIsDirectMessage() {
    return widget.room.client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(widget.room) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isDirectMessage) const tiamat.Text.labelLow("Room Members"),
        Expanded(
          child: SizedBox(
            width: Layout.desktop
                ? isDirectMessage
                    ? widget.compact
                        ? 220
                        : 300
                    : widget.compact
                        ? 180
                        : 200
                : null,
            child: RoomMemberList(
                key: ValueKey(
                    "room-participant-list-key-${widget.room.localId}"),
                widget.room),
          ),
        ),
        if (widget.room is MatrixRoom || widget.forceNicknamesButton) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: Layout.desktop
                ? widget.compact
                    ? 180
                    : 200
                : double.infinity,
            child: tiamat.Button.secondary(
              text: 'Nicknames',
              onTap: () {
                if (widget.room is! MatrixRoom) {
                  widget.onNicknamesPressed?.call();
                  return;
                }

                SettingsNavigation.show(
                  context,
                  RoomSettingsPage(
                    room: widget.room,
                    contextSpace: widget.contextSpace,
                    initialTabId: SettingsCategoryRoom.tabIdNicknames,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
