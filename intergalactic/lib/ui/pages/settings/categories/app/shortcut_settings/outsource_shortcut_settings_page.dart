import 'package:intergalactic/ui/pages/settings/categories/app/shortcut_settings/keyboard_hook_shortcuts_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class OutsourceShortcutSettingsPage extends StatelessWidget {
  const OutsourceShortcutSettingsPage({super.key});

  String get labelSystemKeyboardShortcutsOutsourceDescription => Intl.message(
        "In your current environment, keyboard shortcuts must be configured in your system settings.",
        name: "labelSystemKeyboardShortcutsOutsourceDescription",
      );

  String get promptSystemKeyboardShortcutsMoreInfo => Intl.message("More Info",
      name: "promptSystemKeyboardShortcutsMoreInfo",
      desc:
          "Prompt for a button on the system keyboard shortcut page, which opens a webpage that provides further information about keyboard shortcuts setup");

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: KeyboardHookShortcutsSettingsPage.labelConfigureKeyboardShortcuts,
      showDivider: false,
      children: [
        SettingsControlRow(
          title: labelSystemKeyboardShortcutsOutsourceDescription,
          child: Align(
            alignment: Alignment.centerLeft,
            child: tiamat.Button.secondary(
              text: promptSystemKeyboardShortcutsMoreInfo,
              onTap: () => LinkUtils.open(
                  Uri.parse("https://ourgalaxy.space/info/keyboard-shortcuts")),
            ),
          ),
        )
      ],
    );
  }
}
