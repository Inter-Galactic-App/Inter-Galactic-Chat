import 'dart:async';

import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/room_event_settings.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomGeneralRoomEventsSettings extends StatefulWidget {
  const RoomGeneralRoomEventsSettings(this.room, {super.key});

  final Room room;

  @override
  State<RoomGeneralRoomEventsSettings> createState() =>
      _RoomGeneralRoomEventsSettingsState();
}

class _RoomGeneralRoomEventsSettingsState
    extends State<RoomGeneralRoomEventsSettings> {
  late RoomEventSettings settings;
  StreamSubscription<void>? _roomUpdateSubscription;
  bool savingJoinEvents = false;
  bool savingLeaveEvents = false;
  bool savingInviteEvents = false;
  bool savingProfileUpdates = false;

  bool get canEdit => widget.room.permissions.canEditRoomEvents;

  String get labelRoomEventsTitle => Intl.message(
        "Room Events",
        desc: "Header for room event visibility settings",
        name: "labelRoomEventsTitle",
      );

  String get labelRoomEventsJoinTitle => Intl.message(
        "Join events",
        desc: "Label for the room setting that shows or hides join events",
        name: "labelRoomEventsJoinTitle",
      );

  String get labelRoomEventsJoinDescription => Intl.message(
        "Show messages when someone joins this room.",
        desc:
            "Description for the room setting that shows or hides join events",
        name: "labelRoomEventsJoinDescription",
      );

  String get labelRoomEventsLeaveTitle => Intl.message(
        "Leave events",
        desc: "Label for the room setting that shows or hides leave events",
        name: "labelRoomEventsLeaveTitle",
      );

  String get labelRoomEventsLeaveDescription => Intl.message(
        "Show messages when someone leaves or is kicked from this room.",
        desc:
            "Description for the room setting that shows or hides leave events",
        name: "labelRoomEventsLeaveDescription",
      );

  String get labelRoomEventsInviteTitle => Intl.message(
        "Invite events",
        desc: "Label for the room setting that shows or hides invite events",
        name: "labelRoomEventsInviteTitle",
      );

  String get labelRoomEventsInviteDescription => Intl.message(
        "Show messages when invites are sent, accepted, rejected, or withdrawn.",
        desc:
            "Description for the room setting that shows or hides invite events",
        name: "labelRoomEventsInviteDescription",
      );

  String get labelRoomEventsProfileUpdatesTitle => Intl.message(
        "Profile account updates",
        desc:
            "Label for the room setting that shows or hides profile account updates",
        name: "labelRoomEventsProfileUpdatesTitle",
      );

  String get labelRoomEventsProfileUpdatesDescription => Intl.message(
        "Show messages when someone changes their display name or avatar in this room.",
        desc:
            "Description for the room setting that shows or hides profile account updates",
        name: "labelRoomEventsProfileUpdatesDescription",
      );

  String get labelRoomEventsAdminControlledDescription => Intl.message(
        "These settings are controlled by room admins.",
        desc: "Description shown when room event settings are read-only",
        name: "labelRoomEventsAdminControlledDescription",
      );

  @override
  void initState() {
    super.initState();
    settings = widget.room.roomEventSettings;
    _roomUpdateSubscription = widget.room.onUpdate.listen((_) {
      if (!mounted) {
        return;
      }

      setState(() {
        settings = widget.room.roomEventSettings;
      });
    });
  }

  @override
  void dispose() {
    _roomUpdateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: labelRoomEventsTitle,
      children: [
        if (!canEdit)
          SettingsControlRow(
            title: 'Admin controlled',
            description: labelRoomEventsAdminControlledDescription,
          ),
        buildToggle(
          title: labelRoomEventsJoinTitle,
          description: labelRoomEventsJoinDescription,
          value: settings.showJoinEvents,
          saving: savingJoinEvents,
          onChanged: onJoinEventsChanged,
        ),
        buildToggle(
          title: labelRoomEventsLeaveTitle,
          description: labelRoomEventsLeaveDescription,
          value: settings.showLeaveEvents,
          saving: savingLeaveEvents,
          onChanged: onLeaveEventsChanged,
        ),
        buildToggle(
          title: labelRoomEventsInviteTitle,
          description: labelRoomEventsInviteDescription,
          value: settings.showInviteEvents,
          saving: savingInviteEvents,
          onChanged: onInviteEventsChanged,
        ),
        buildToggle(
          title: labelRoomEventsProfileUpdatesTitle,
          description: labelRoomEventsProfileUpdatesDescription,
          value: settings.showProfileAccountUpdates,
          saving: savingProfileUpdates,
          onChanged: onProfileUpdatesChanged,
        ),
      ],
    );
  }

  Widget buildToggle({
    required String title,
    required String description,
    required bool value,
    required bool saving,
    required ValueChanged<bool> onChanged,
  }) {
    return IgnorePointer(
      ignoring: !canEdit || saving,
      child: Opacity(
        opacity: canEdit ? 1 : 0.6,
        child: SettingsControlRow(
          title: title,
          description: description,
          semanticValue: saving ? 'Saving' : settingsToggleStateLabel(value),
          toggled: value,
          semanticOnTapHint: value ? 'Turn off' : 'Turn on',
          onActivate: canEdit && !saving ? () => onChanged(!value) : null,
          enabled: canEdit && !saving,
          excludeChildSemantics: !saving,
          trailing: saving
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : SettingsSwitchStateLabel(
                  value: value,
                  child: ExcludeFocus(
                    child: tiamat.Switch(
                      state: value,
                      onChanged: onChanged,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> onJoinEventsChanged(bool value) async {
    final previous = settings;
    final next = settings.copyWith(showJoinEvents: value);

    setState(() {
      settings = next;
      savingJoinEvents = true;
    });

    try {
      await widget.room.setRoomEventSettings(next);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          settings = previous;
        });
        await AdaptiveDialog.showError(context, error, stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() {
          savingJoinEvents = false;
        });
      }
    }
  }

  Future<void> onLeaveEventsChanged(bool value) async {
    final previous = settings;
    final next = settings.copyWith(showLeaveEvents: value);

    setState(() {
      settings = next;
      savingLeaveEvents = true;
    });

    try {
      await widget.room.setRoomEventSettings(next);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          settings = previous;
        });
        await AdaptiveDialog.showError(context, error, stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() {
          savingLeaveEvents = false;
        });
      }
    }
  }

  Future<void> onInviteEventsChanged(bool value) async {
    final previous = settings;
    final next = settings.copyWith(showInviteEvents: value);

    setState(() {
      settings = next;
      savingInviteEvents = true;
    });

    try {
      await widget.room.setRoomEventSettings(next);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          settings = previous;
        });
        await AdaptiveDialog.showError(context, error, stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() {
          savingInviteEvents = false;
        });
      }
    }
  }

  Future<void> onProfileUpdatesChanged(bool value) async {
    final previous = settings;
    final next = settings.copyWith(showProfileAccountUpdates: value);

    setState(() {
      settings = next;
      savingProfileUpdates = true;
    });

    try {
      await widget.room.setRoomEventSettings(next);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          settings = previous;
        });
        await AdaptiveDialog.showError(context, error, stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() {
          savingProfileUpdates = false;
        });
      }
    }
  }
}
