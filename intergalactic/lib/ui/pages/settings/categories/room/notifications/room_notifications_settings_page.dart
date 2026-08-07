import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' as material;
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/general/room_general_chat_privacy.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/notifications/room_notifications_settings_view.dart';
import 'package:intergalactic/ui/pages/settings/settings_compact_action_button.dart';
import 'package:intergalactic/utils/custom_sound_manager.dart';
import 'package:intergalactic/utils/error_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomNotificationsSettingsPage extends StatefulWidget {
  const RoomNotificationsSettingsPage({
    super.key,
    required this.room,
    this.contextLabel = 'room',
  });
  final Room room;
  final String contextLabel;

  @override
  State<RoomNotificationsSettingsPage> createState() =>
      _RoomNotificationsSettingsPageState();
}

class _RoomNotificationsSettingsPageState
    extends State<RoomNotificationsSettingsPage> {
  late PushRule pushRule;
  StreamSubscription<void>? _roomUpdateSubscription;
  StreamSubscription? _preferencesSubscription;
  bool isPickingRoomNotificationSound = false;

  @override
  void initState() {
    super.initState();
    _preferencesSubscription = preferences.onSettingChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    _subscribeToRoom();
  }

  @override
  void didUpdateWidget(covariant RoomNotificationsSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) {
      _subscribeToRoom();
    }
  }

  void _subscribeToRoom() {
    _roomUpdateSubscription?.cancel();
    pushRule = widget.room.pushRule;
    _roomUpdateSubscription = widget.room.onUpdate.listen((_) {
      if (!mounted) return;

      setState(() {
        pushRule = widget.room.pushRule;
      });
    });
  }

  @override
  void dispose() {
    _roomUpdateSubscription?.cancel();
    _preferencesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoomNotificationsSettingsView(
          pushRule: pushRule,
          contextLabel: widget.contextLabel,
          onPushRuleChanged: (rule) {
            unawaited(setPushRule(rule));
          },
        ),
        _RoomNotificationSnoozePanel(
          room: widget.room,
          contextLabel: widget.contextLabel,
          onChanged: () {
            if (mounted) {
              setState(() {});
            }
          },
        ),
        RoomGeneralChatPrivacySettings(widget.room),
        if (supportsDesktopRoomNotificationSounds) ...[
          _RoomNotificationSoundPanel(
            currentValueLabel: CustomSoundManager.roomNotificationSoundLabel(
              widget.room.identifier,
            ),
            contextLabel: widget.contextLabel,
            hasOverride: CustomSoundManager.hasRoomNotificationSound(
              widget.room.identifier,
            ),
            volume: preferences.getEffectiveRoomNotificationVolume(
              widget.room.identifier,
            ),
            hasVolumeOverride: preferences.getRoomNotificationVolume(
                  widget.room.identifier,
                ) !=
                null,
            isBusy: isPickingRoomNotificationSound,
            onChoose: pickRoomNotificationSound,
            onPreview: previewRoomNotificationSound,
            onReset: resetRoomNotificationSound,
            onVolumeChanged: setRoomNotificationVolume,
            onVolumeReset: resetRoomNotificationVolume,
          ),
        ],
      ],
    );
  }

  bool get supportsDesktopRoomNotificationSounds =>
      PlatformUtils.isWindows || PlatformUtils.isLinux;

  Future<void> setPushRule(PushRule? rule) async {
    if (rule == null || rule == pushRule) return;

    setState(() {
      pushRule = rule;
    });

    await ErrorUtils.tryRun(context, () async {
      await widget.room.setPushRule(rule);
    });

    if (!mounted) return;

    setState(() {
      pushRule = widget.room.pushRule;
    });
  }

  Future<void> pickRoomNotificationSound() async {
    if (isPickingRoomNotificationSound) {
      return;
    }

    final roomId = widget.room.identifier;

    setState(() {
      isPickingRoomNotificationSound = true;
    });

    try {
      await ErrorUtils.tryRun(context, () async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: CustomSoundManager.allowedExtensions,
          dialogTitle: widget.contextLabel == 'space'
              ? 'Pick space notification sound'
              : 'Pick room notification sound',
        );

        final file =
            result == null || result.files.isEmpty ? null : result.files.first;
        if (file?.path == null) {
          return;
        }

        final previousPath = preferences.getRoomNotificationSoundPath(roomId);
        final importedPath =
            await CustomSoundManager.importRoomNotificationSound(
          file!.path!,
          roomLocalId: roomId,
        );

        if (previousPath != importedPath) {
          try {
            await preferences.setRoomNotificationSoundPath(
                roomId, importedPath);
          } catch (_) {
            await CustomSoundManager.deleteImportedSound(importedPath);
            rethrow;
          }
          await CustomSoundManager.deleteImportedSound(previousPath);
        }

        if (mounted) {
          setState(() {});
        }
      });
    } finally {
      if (!mounted) {
        return;
      }

      setState(() {
        isPickingRoomNotificationSound = false;
      });
    }
  }

  Future<void> resetRoomNotificationSound() async {
    if (isPickingRoomNotificationSound) {
      return;
    }

    final roomId = widget.room.identifier;
    final previousPath = preferences.getRoomNotificationSoundPath(roomId);

    await ErrorUtils.tryRun(context, () async {
      await preferences.setRoomNotificationSoundPath(roomId, null);
      await CustomSoundManager.deleteImportedSound(previousPath);
    });

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> setRoomNotificationVolume(double volume) async {
    await ErrorUtils.tryRun(context, () async {
      await preferences.setRoomNotificationVolume(
        widget.room.identifier,
        volume,
      );
    });

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> resetRoomNotificationVolume() async {
    await ErrorUtils.tryRun(context, () async {
      await preferences.setRoomNotificationVolume(
        widget.room.identifier,
        null,
      );
    });

    if (mounted) {
      setState(() {});
    }
  }

  void previewRoomNotificationSound() {
    if (isPickingRoomNotificationSound) {
      return;
    }

    final roomId = widget.room.identifier;

    unawaited(ErrorUtils.tryRun(context, () async {
      final player = NotificationManager.getSoundPlayer(
        roomLocalId: roomId,
      );
      player.setPlaylistMode(PlaylistMode.none);
      await player.open(Media(
        CustomSoundManager.notificationSoundUri(
          roomLocalId: roomId,
        ),
      ));
    }));
  }
}

class _RoomNotificationSnoozePanel extends StatelessWidget {
  const _RoomNotificationSnoozePanel({
    required this.room,
    required this.contextLabel,
    required this.onChanged,
  });

  final Room room;
  final String contextLabel;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final snooze = preferences.getRoomNotificationSnooze(
      clientId: room.client.identifier,
      roomId: room.identifier,
    );
    final displayContext = contextLabel == 'space' ? 'space' : 'room';

    return SettingsSection(
      title: 'Temporary Snooze',
      children: [
        SettingsControlRow(
          title: 'Snooze notifications',
          description: snooze == null
              ? 'Temporarily suppress notifications from this $displayContext on this device.'
              : 'Snoozed until ${_formatSnoozeUntil(context, snooze)}. '
                  '${formatRoomNotificationSnoozeRemaining(snooze)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option
                      in RoomNotificationSnoozeDurationOption.values)
                    SettingsCompactActionButton(
                      label: option.compactLabel,
                      semanticLabel: 'Snooze ${option.label}',
                      onTap: () => unawaited(_setSnooze(context, option)),
                    ),
                  if (snooze != null)
                    SettingsCompactActionButton(
                      label: 'Unsnooze',
                      onTap: () => unawaited(_clearSnooze(context)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _setSnooze(
    BuildContext context,
    RoomNotificationSnoozeDurationOption option,
  ) async {
    var changed = false;
    await ErrorUtils.tryRun(context, () async {
      await preferences.setRoomNotificationSnooze(
        clientId: room.client.identifier,
        roomId: room.identifier,
        duration: option.duration,
        source: 'room_settings',
      );
      await NotificationManager.clearNotifications(room);
      changed = true;
    });
    if (changed) {
      onChanged();
    }
  }

  Future<void> _clearSnooze(BuildContext context) async {
    await ErrorUtils.tryRun(context, () async {
      await preferences.clearRoomNotificationSnooze(
        clientId: room.client.identifier,
        roomId: room.identifier,
      );
    });
    onChanged();
  }

  String _formatSnoozeUntil(
    BuildContext context,
    RoomNotificationSnooze snooze,
  ) {
    final date = snooze.snoozedUntil;
    final time = material.TimeOfDay.fromDateTime(date).format(context);
    return '${date.month}/${date.day} at $time';
  }
}

class _RoomNotificationSoundPanel extends StatelessWidget {
  const _RoomNotificationSoundPanel({
    required this.currentValueLabel,
    required this.contextLabel,
    required this.hasOverride,
    required this.volume,
    required this.hasVolumeOverride,
    required this.isBusy,
    required this.onChoose,
    required this.onPreview,
    required this.onReset,
    required this.onVolumeChanged,
    required this.onVolumeReset,
  });

  final String currentValueLabel;
  final String contextLabel;
  final bool hasOverride;
  final double volume;
  final bool hasVolumeOverride;
  final bool isBusy;
  final VoidCallback onChoose;
  final VoidCallback onPreview;
  final VoidCallback onReset;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onVolumeReset;

  @override
  Widget build(BuildContext context) {
    final displayContext = contextLabel == 'space' ? 'space' : 'room';

    return SettingsSection(
      title: 'Desktop Sound',
      showDivider: false,
      children: [
        SettingsControlRow(
          title: '${_capitalize(displayContext)} notification sound',
          description:
              'Choose a local notification sound for this $displayContext on desktop.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tiamat.Text.labelLow(currentValueLabel),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: tiamat.Button.secondary(
                      text: isBusy ? 'Choosing...' : 'Choose File',
                      onTap: isBusy ? null : onChoose,
                    ),
                  ),
                  const SizedBox(width: 8),
                  tiamat.Tooltip(
                    text: 'Preview sound',
                    child: tiamat.CircleButton(
                      icon: material.Icons.play_arrow,
                      onPressed: isBusy ? null : onPreview,
                    ),
                  ),
                  const SizedBox(width: 8),
                  tiamat.Tooltip(
                    text: 'Use app notification sound',
                    child: tiamat.CircleButton(
                      icon: material.Icons.restart_alt,
                      onPressed: hasOverride && !isBusy ? onReset : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SettingsControlRow(
          title: '${_capitalize(displayContext)} notification volume',
          description: hasVolumeOverride
              ? 'This $displayContext uses its own notification volume.'
              : 'Using the app notification volume until you adjust this slider.',
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: tiamat.Text.labelLow(
                  '${volume.toStringAsFixed(0)}%',
                ),
              ),
              Expanded(
                child: tiamat.Slider(
                  value: volume,
                  min: 0,
                  max: 150,
                  onChanged: (newValue) {
                    onVolumeChanged(
                      double.parse(newValue.toStringAsFixed(0)),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              tiamat.Tooltip(
                text: 'Use app notification volume',
                child: tiamat.CircleButton(
                  icon: material.Icons.restart_alt,
                  onPressed:
                      hasVolumeOverride && !isBusy ? onVolumeReset : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
