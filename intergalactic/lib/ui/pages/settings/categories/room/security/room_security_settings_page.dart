import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_history_sharing.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/room_creator.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/error_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'package:tiamat/tiamat.dart' as tiamat;

class RoomSecuritySettingsPage extends StatefulWidget {
  const RoomSecuritySettingsPage({
    required this.room,
    this.contextSpace,
    this.showEncryptionToggle = true,
    super.key,
  });
  final Room room;
  final Space? contextSpace;
  final bool showEncryptionToggle;

  @override
  State<RoomSecuritySettingsPage> createState() =>
      _RoomSecuritySettingsPageState();
}

class _RoomSecuritySettingsPageState extends State<RoomSecuritySettingsPage> {
  late bool isE2EEEnabled;
  late RoomVisibility visibility;
  matrix.HistoryVisibility? historyVisibility;

  String get promptEnableEncryptionRoomSettings =>
      Intl.message("Enable Encryption",
          name: "promptEnableEncryptionRoomSettings",
          desc: "Short prompt to enable encryption for a room");

  String get encryptionCannotBeDisabledExplanationRoomSettings =>
      Intl.message("If enabled, encryption cannot be disabled later",
          name: "encryptionCannotBeDisabledExplanationRoomSettings",
          desc: "Explains that encryption cannot be disabled once enabled");

  @override
  void initState() {
    isE2EEEnabled = widget.room.isE2EE;
    visibility = widget.room.visibility;
    if (widget.room case MatrixRoom matrixRoom) {
      historyVisibility = matrixRoom.matrixRoom.historyVisibility;
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Access',
      children: [
        if (widget.room.client.supportsE2EE && widget.showEncryptionToggle)
          buildE2EEToggle(),
        buildRoomVisibility(),
        if (widget.room case MatrixRoom matrixRoom)
          buildHistoryVisibility(matrixRoom),
      ],
    );
  }

  Widget buildE2EEToggle() {
    return Opacity(
      opacity: widget.room.permissions.canEnableE2EE ? 1 : 0.5,
      child: SettingsControlRow(
        title: promptEnableEncryptionRoomSettings,
        description: encryptionCannotBeDisabledExplanationRoomSettings,
        trailing: IgnorePointer(
          ignoring: isE2EEEnabled || !widget.room.permissions.canEnableE2EE,
          child: tiamat.Switch(
            state: isE2EEEnabled,
            onChanged: (value) {
              if (value != true) return;
              setState(() {
                isE2EEEnabled = true;
                widget.room.enableE2EE();
              });
            },
          ),
        ),
      ),
    );
  }

  Widget buildRoomVisibility() {
    return IgnorePointer(
      ignoring: !widget.room.permissions.canChangeVisibility,
      child: Opacity(
        opacity: widget.room.permissions.canChangeVisibility ? 1 : 0.5,
        child: SettingsControlRow(
          title: 'Room Visibility',
          description:
              'Choose whether this room is private, public, or restricted to a space.',
          child: _VisibilityCard(
            onTap: () async {
              List<String> spaces = List.empty(growable: true);
              if (widget.room.visibility
                  case RoomVisibilityRestricted restricted) {
                spaces.addAll(restricted.spaces);
              }

              if (widget.contextSpace != null &&
                  !spaces.contains(widget.contextSpace?.identifier)) {
                spaces.add(widget.contextSpace!.identifier);
              }

              if (spaces.isEmpty) {
                var parents = widget.room.client.spaces.where((i) => i.subspaces
                    .any((i) => i.identifier == widget.room.identifier));

                for (var p in parents) {
                  spaces.add(p.identifier);
                }
              }

              var items = [
                if (spaces.isNotEmpty) RoomVisibilityRestricted(spaces),
                RoomVisibilityPrivate(),
                RoomVisibilityPublic(),
              ];

              var newVisibility = await AdaptiveDialog.pickOne(
                title: "Set Visibility",
                context,
                items: items,
                itemBuilder: (context, item, callback) {
                  return Material(
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: callback,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: RoomFieldVisibility.buildRoomVisibility(
                            widget.room.client, item),
                      ),
                    ),
                  );
                },
              );

              if (newVisibility != null) {
                ErrorUtils.tryRun(context, () async {
                  await widget.room.setVisibility(newVisibility);

                  setState(() {
                    visibility = newVisibility;
                  });
                });
              }
            },
            child: RoomFieldVisibility.buildRoomVisibility(
              widget.room.client,
              visibility,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildHistoryVisibility(MatrixRoom room) {
    final canChange = room.matrixRoom.canChangeHistoryVisibility;
    final selected = historyVisibility ?? matrix.HistoryVisibility.invited;
    final options = <matrix.HistoryVisibility>[
      matrix.HistoryVisibility.invited,
      matrix.HistoryVisibility.joined,
      matrix.HistoryVisibility.shared,
      matrix.HistoryVisibility.worldReadable,
    ];

    return IgnorePointer(
      ignoring: !canChange,
      child: Opacity(
        opacity: canChange ? 1 : 0.5,
        child: SettingsControlRow(
          title: 'Room History',
          description:
              'Choose how much room history members may see. In encrypted rooms, Members (full history) means locally available encryption keys may be shared with newly invited eligible devices.',
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280, minWidth: 220),
            child: tiamat.DropdownSelector<matrix.HistoryVisibility>(
              color: Theme.of(context).colorScheme.surfaceContainer,
              value: selected,
              items: options,
              itemBuilder: (item) => tiamat.Text.label(
                _historyVisibilityLabel(item),
                overflow: TextOverflow.ellipsis,
              ),
              onItemSelected: (item) {
                if (item == null) return;
                ErrorUtils.tryRun(context, () async {
                  await room.matrixRoom.setHistoryVisibility(item);
                  setState(() {
                    historyVisibility = item;
                  });
                });
              },
            ),
          ),
          child: _HistoryVisibilityNotice(
            visibility: selected,
            encrypted: room.isE2EE,
          ),
        ),
      ),
    );
  }

  String _historyVisibilityLabel(matrix.HistoryVisibility visibility) {
    return switch (visibility) {
      matrix.HistoryVisibility.invited => 'Invited members',
      matrix.HistoryVisibility.joined => 'Joined members',
      matrix.HistoryVisibility.shared => 'Members (full history)',
      matrix.HistoryVisibility.worldReadable => 'Anyone (world readable)',
    };
  }
}

class _VisibilityCard extends StatelessWidget {
  const _VisibilityCard({
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.72),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HistoryVisibilityNotice extends StatelessWidget {
  const _HistoryVisibilityNotice({
    required this.visibility,
    required this.encrypted,
  });

  final matrix.HistoryVisibility visibility;
  final bool encrypted;

  @override
  Widget build(BuildContext context) {
    if (!encrypted || !matrixHistoryVisibilityAllowsInviteSharing(visibility)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Newly invited members can receive shared encrypted history on devices allowed by the sender\'s key-sharing policy. Use this only when the room expects admins to share prior conversation.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
