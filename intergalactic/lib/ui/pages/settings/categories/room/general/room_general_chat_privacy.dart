import 'package:intergalactic/client/components/read_receipts/read_receipt_component.dart';
import 'package:intergalactic/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomGeneralChatPrivacySettings extends StatefulWidget {
  const RoomGeneralChatPrivacySettings(this.room);

  final Room room;

  @override
  State<RoomGeneralChatPrivacySettings> createState() =>
      _RoomGeneralChatPrivacySettings();
}

class _RoomGeneralChatPrivacySettings
    extends State<RoomGeneralChatPrivacySettings> {
  bool? publicReadReceiptsForRoom;
  bool? typingIndicatorEnabledForRoom;

  String labelDefaultReadReceiptsOption(pref) => Intl.message(
    "Use global preference ($pref)",
    desc:
        "Label to use the global preference, showing the current global preference value",
    name: "labelDefaultReadReceiptsOption",
    args: [pref],
  );

  String labelDefaultTypingIndicatorsOption(pref) => Intl.message(
    "Use global preference ($pref)",
    desc:
        "Label to use the global preference, showing the current global preference value",
    name: "labelDefaultTypingIndicatorsOption",
    args: [pref],
  );

  String get labelReadReceiptsTitle => Intl.message(
    "Read receipts",
    desc:
        "Label for the toggle for enabling and disabling public read receipts",
    name: "labelReadReceiptsTitle",
  );

  String get labelTypingIndicatorTitle => Intl.message(
    "Typing indicators",
    desc: "Label for the toggle for enabling and disabling typing indicators",
    name: "labelTypingIndicatorTitle",
  );

  String get labelRoomPrivacyNotificationSettings => Intl.message(
    "Privacy",
    desc: "Header for room privacy notification settings",
    name: "labelRoomPrivacyNotificationSettings",
  );

  @override
  void initState() {
    setState(() {
      publicReadReceiptsForRoom = widget.room
          .getComponent<ReadReceiptComponent>()!
          .usePublicReadReceiptsForRoom;
      typingIndicatorEnabledForRoom = widget.room
          .getComponent<TypingIndicatorComponent>()!
          .typingIndicatorEnabledForRoom;
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: labelRoomPrivacyNotificationSettings,
      children: [
        SettingsControlRow(
          title: labelReadReceiptsTitle,
          description:
              'Override whether read receipts are public in this room.',
          trailing: publicReadReceiptsSettings(),
        ),
        SettingsControlRow(
          title: labelTypingIndicatorTitle,
          description:
              'Override whether typing indicators are sent in this room.',
          trailing: publicTypingIndicatorSettings(),
        ),
      ],
    );
  }

  Widget publicReadReceiptsSettings() {
    var usePublicReadReceipts = widget.room.client
        .getComponent<UserPresenceComponent>()!
        .usePublicReadReceipts;
    return _PreferenceDropdown<bool?>(
      value: publicReadReceiptsForRoom,
      options: [
        _PreferenceDropdownOption(
          value: null,
          label: labelDefaultReadReceiptsOption(
            usePublicReadReceipts
                ? CommonStrings.labelPublic
                : CommonStrings.labelPrivate,
          ),
        ),
        _PreferenceDropdownOption(
          value: false,
          label: CommonStrings.labelPrivate,
        ),
        _PreferenceDropdownOption(
          value: true,
          label: CommonStrings.labelPublic,
        ),
      ],
      onChanged: onReadReceiptPrefChanged,
    );
  }

  Widget publicTypingIndicatorSettings() {
    var typingIndicatorEnabled = widget.room.client
        .getComponent<UserPresenceComponent>()!
        .typingIndicatorEnabled;
    return _PreferenceDropdown<bool?>(
      value: typingIndicatorEnabledForRoom,
      options: [
        _PreferenceDropdownOption(
          value: null,
          label: labelDefaultTypingIndicatorsOption(
            typingIndicatorEnabled
                ? CommonStrings.labelEnabled
                : CommonStrings.labelDisabled,
          ),
        ),
        _PreferenceDropdownOption(
          value: false,
          label: CommonStrings.labelDisabled,
        ),
        _PreferenceDropdownOption(
          value: true,
          label: CommonStrings.labelEnabled,
        ),
      ],
      onChanged: onTypingIndicatorPrefChanged,
    );
  }

  Future<void> onReadReceiptPrefChanged(bool? value) async {
    widget.room
        .getComponent<ReadReceiptComponent>()!
        .setUsePublicReadReceiptsForRoom(value);
    setState(() => publicReadReceiptsForRoom = value);
  }

  Future<void> onTypingIndicatorPrefChanged(bool? value) async {
    widget.room
        .getComponent<TypingIndicatorComponent>()!
        .setTypingIndicatorEnabledForRoom(value);
    setState(() => typingIndicatorEnabledForRoom = value);
  }
}

class _PreferenceDropdownOption<T> {
  const _PreferenceDropdownOption({required this.value, required this.label});

  final T value;
  final String label;
}

class _PreferenceDropdown<T> extends StatelessWidget {
  const _PreferenceDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<_PreferenceDropdownOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280, minWidth: 220),
      child: tiamat.DropdownSelector<_PreferenceDropdownOption<T>>(
        color: Theme.of(context).colorScheme.surfaceContainer,
        value: selected,
        items: options,
        itemBuilder: (item) =>
            tiamat.Text.label(item.label, overflow: TextOverflow.ellipsis),
        onItemSelected: (item) {
          if (item == null) return;
          onChanged(item.value);
        },
      ),
    );
  }
}
