import 'dart:async';

import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/message_background_settings.dart';
import 'package:flutter/widgets.dart';

class RoomAppearanceSettingsPage extends StatefulWidget {
  const RoomAppearanceSettingsPage({super.key, required this.room});
  final Room room;
  @override
  State<RoomAppearanceSettingsPage> createState() =>
      _RoomAppearanceSettingsPageState();
}

class _RoomAppearanceSettingsPageState
    extends State<RoomAppearanceSettingsPage> {
  late StreamSubscription _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.room.onUpdate.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (BuildConfig.MOBILE || BuildConfig.DESKTOP)
          MessageBackgroundSettings(
            title: "Room background",
            description: "Overrides the default background in this room",
            storageKey: "room:${widget.room.localId}",
            value: preferences.getRoomMessageBackgroundPath(
              widget.room.localId,
            ),
            backgroundOpacity: preferences.getEffectiveMessageBackgroundOpacity(
              widget.room.localId,
            ),
            backgroundOpacityInherited:
                preferences.getRoomMessageBackgroundOpacity(
                      widget.room.localId,
                    ) ==
                    null,
            backgroundOpacityClearText: "Inherit Default",
            sentBubbleColorHex: preferences.getEffectiveSentMessageBubbleColor(
              widget.room.localId,
            ),
            sentBubbleColorInherited: preferences
                    .getRoomSentMessageBubbleColor(widget.room.localId) ==
                null,
            receivedBubbleColorHex:
                preferences.getEffectiveReceivedMessageBubbleColor(
              widget.room.localId,
            ),
            receivedBubbleColorInherited:
                preferences.getRoomReceivedMessageBubbleColor(
                      widget.room.localId,
                    ) ==
                    null,
            bubbleColorClearText: "Inherit Default",
            clearText: "Inherit Default",
            onChanged: (path) async {
              await preferences.setRoomMessageBackgroundPath(
                widget.room.localId,
                path,
              );
              if (mounted) setState(() {});
            },
            onBackgroundOpacityChanged: (value) async {
              await preferences.setRoomMessageBackgroundOpacity(
                widget.room.localId,
                value,
              );
              if (mounted) setState(() {});
            },
            onClearBackgroundOpacity: () async {
              await preferences.setRoomMessageBackgroundOpacity(
                widget.room.localId,
                null,
              );
              if (mounted) setState(() {});
            },
            onSentBubbleColorChanged: (hexColor) async {
              await preferences.setRoomSentMessageBubbleColor(
                widget.room.localId,
                hexColor,
              );
              if (mounted) setState(() {});
            },
            onClearSentBubbleColor: () async {
              await preferences.setRoomSentMessageBubbleColor(
                widget.room.localId,
                null,
              );
              if (mounted) setState(() {});
            },
            onReceivedBubbleColorChanged: (hexColor) async {
              await preferences.setRoomReceivedMessageBubbleColor(
                widget.room.localId,
                hexColor,
              );
              if (mounted) setState(() {});
            },
            onClearReceivedBubbleColor: () async {
              await preferences.setRoomReceivedMessageBubbleColor(
                widget.room.localId,
                null,
              );
              if (mounted) setState(() {});
            },
          ),
      ],
    );
  }
}
