import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/dm_pin_dialog.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DmLockPreferences<T extends Client> extends StatefulWidget {
  const DmLockPreferences({
    required this.client,
    this.showPanel = true,
    super.key,
  });

  final T client;
  final bool showPanel;

  @override
  State<DmLockPreferences<T>> createState() => _DmLockPreferencesState<T>();
}

class _DmLockPreferencesState<T extends Client>
    extends State<DmLockPreferences<T>> {
  StreamSubscription? _preferencesSubscription;

  bool get _hasPin => dmLockController.isPinConfiguredForClient(widget.client);

  List<Room> get _lockedRooms =>
      dmLockController.getLockedRoomsForClient(widget.client);

  @override
  void initState() {
    super.initState();
    _preferencesSubscription =
        preferences.onSettingChanged.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _preferencesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow(
          "Protect sensitive direct messages with a local PIN on this device. The PIN is stored locally only and is never sent to Matrix.",
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!_hasPin)
              tiamat.Button(
                text: "Set PIN",
                onTap: _setPin,
              ),
            if (_hasPin)
              tiamat.Button(
                text: "Change PIN",
                onTap: _changePin,
              ),
            if (_hasPin)
              tiamat.Button.secondary(
                text: "Remove PIN",
                onTap: _removePin,
              ),
          ],
        ),
        const SizedBox(height: 16),
        tiamat.Text.labelEmphasised("Locked DMs"),
        const SizedBox(height: 6),
        if (_lockedRooms.isEmpty)
          tiamat.Text.labelLow(
            "No direct messages are currently locked on this device.",
          ),
        if (_lockedRooms.isNotEmpty)
          Column(
            children: [
              for (final room in _lockedRooms)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Icon(
                            dmLockController.isRoomUnlocked(room)
                                ? Icons.lock_open_rounded
                                : Icons.lock_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                tiamat.Text.labelEmphasised(
                                  room.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                tiamat.Text.labelLow(
                                  dmLockController.isRoomUnlocked(room)
                                      ? "Unlocked for this session"
                                      : "PIN required before opening",
                                ),
                              ],
                            ),
                          ),
                          tiamat.IconButton(
                            icon: Icons.lock_open_rounded,
                            onPressed: () async {
                              await dmLockController.setRoomLocked(
                                room,
                                false,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );

    if (!widget.showPanel) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: content,
      );
    }

    return tiamat.Panel(
      header: "Direct Message Lock",
      mode: tiamat.TileType.surfaceContainerLow,
      child: content,
    );
  }

  Future<void> _setPin() async {
    final result = await AdaptiveDialog.show<DmPinDialogResult>(
      context,
      title: "Set PIN",
      builder: (_) => const DmPinDialog(
        mode: DmPinDialogMode.setPin,
        description:
            "Choose a numeric PIN with at least 4 digits for locked direct messages on this device.",
        submitLabel: "Save PIN",
      ),
    );

    final newPin = result?.newPin;
    if (newPin == null || newPin.isEmpty) {
      return;
    }

    await dmLockController.setPinForClient(widget.client, newPin);
  }

  Future<void> _changePin() async {
    final result = await AdaptiveDialog.show<DmPinDialogResult>(
      context,
      title: "Change PIN",
      builder: (_) => const DmPinDialog(
        mode: DmPinDialogMode.changePin,
        description:
            "Enter your current PIN, then choose a new numeric PIN for locked direct messages.",
        submitLabel: "Update PIN",
      ),
    );

    if (result == null ||
        result.currentPin == null ||
        result.currentPin!.isEmpty ||
        result.newPin == null ||
        result.newPin!.isEmpty) {
      return;
    }

    final verified = await dmLockController.verifyPinForClient(
      widget.client,
      result.currentPin!,
    );
    if (!verified) {
      await AdaptiveDialog.show(
        context,
        title: "Incorrect PIN",
        builder: (_) => tiamat.Text.label(
          "The current PIN did not match.",
        ),
      );
      return;
    }

    await dmLockController.setPinForClient(widget.client, result.newPin!);
  }

  Future<void> _removePin() async {
    final result = await AdaptiveDialog.show<DmPinDialogResult>(
      context,
      title: "Remove PIN",
      builder: (_) => const DmPinDialog(
        mode: DmPinDialogMode.verify,
        description:
            "Enter your PIN to remove local DM protection from this account on this device.",
        submitLabel: "Remove PIN",
      ),
    );

    final pin = result?.newPin;
    if (pin == null || pin.isEmpty) {
      return;
    }

    final verified = await dmLockController.verifyPinForClient(
      widget.client,
      pin,
    );
    if (!verified) {
      await AdaptiveDialog.show(
        context,
        title: "Incorrect PIN",
        builder: (_) => tiamat.Text.label(
          "The PIN did not match.",
        ),
      );
      return;
    }

    await dmLockController.removePinForClient(widget.client);
  }
}
