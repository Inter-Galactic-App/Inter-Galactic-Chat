import 'dart:async';

import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/member.dart';
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
  StreamSubscription<void>? _roomUpdateSubscription;
  List<Member> _joinRequests = const [];

  @override
  void initState() {
    super.initState();
    isDirectMessage = _computeIsDirectMessage();
    _joinRequests = _readJoinRequests();
    _subscribeRoomUpdates();
  }

  @override
  void didUpdateWidget(covariant RoomMembersListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room == widget.room) {
      return;
    }

    _roomUpdateSubscription?.cancel();
    _subscribeRoomUpdates();

    final nextIsDirectMessage = _computeIsDirectMessage();
    final nextJoinRequests = _readJoinRequests();
    if (nextIsDirectMessage != isDirectMessage ||
        !_sameMemberIds(nextJoinRequests, _joinRequests)) {
      setState(() {
        isDirectMessage = nextIsDirectMessage;
        _joinRequests = nextJoinRequests;
      });
    } else {
      isDirectMessage = nextIsDirectMessage;
      _joinRequests = nextJoinRequests;
    }
  }

  @override
  void dispose() {
    _roomUpdateSubscription?.cancel();
    super.dispose();
  }

  void _subscribeRoomUpdates() {
    _roomUpdateSubscription = widget.room.onUpdate.listen((_) {
      final nextJoinRequests = _readJoinRequests();
      if (_sameMemberIds(nextJoinRequests, _joinRequests)) {
        return;
      }

      if (mounted) {
        setState(() {
          _joinRequests = nextJoinRequests;
        });
      }
    });
  }

  bool _computeIsDirectMessage() {
    return widget.room.client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(widget.room) ??
        false;
  }

  List<Member> _readJoinRequests() {
    final room = widget.room;
    if (room is! RoomJoinRequestActions) {
      return const <Member>[];
    }
    if (!room.permissions.canInviteUser && !room.permissions.canKick) {
      return const <Member>[];
    }

    return (room as RoomJoinRequestActions).joinRequestsList();
  }

  bool _sameMemberIds(List<Member> left, List<Member> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      if (left[index].identifier != right[index].identifier) {
        return false;
      }
    }

    return true;
  }

  String get _joinRequestsLabel {
    final count = _joinRequests.length;
    return count == 1 ? '1 join request' : '$count join requests';
  }

  void _openMembersSettings() {
    SettingsNavigation.show(
      context,
      RoomSettingsPage(
        room: widget.room,
        contextSpace: widget.contextSpace,
        initialTabId: SettingsCategoryRoom.tabIdMembers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isDirectMessage) const tiamat.Text.labelLow("Room Members"),
        if (!isDirectMessage && _joinRequests.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: Layout.desktop
                ? widget.compact
                    ? 180
                    : 200
                : double.infinity,
            child: tiamat.Button.secondary(
              text: _joinRequestsLabel,
              onTap: _openMembersSettings,
            ),
          ),
          const SizedBox(height: 8),
        ],
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
