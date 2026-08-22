import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

class WindowSettingsPage extends StatefulWidget {
  const WindowSettingsPage({super.key});

  @override
  State<WindowSettingsPage> createState() => _WindowSettingsPageState();
}

class _WindowSettingsPageState extends State<WindowSettingsPage> {
  String get labelSettingsWindowBehaviourTitle =>
      Intl.message("Window behaviour",
          desc: "Header for the window behaviour section of settings",
          name: "labelSettingsWindowBehaviourTitle");

  String get labelSettingsMinimizeOnCloseToggle =>
      Intl.message("Minimize on close",
          desc: "Label for the toggle to turn on and off minimize on close",
          name: "labelSettingsMinimizeOnCloseToggle");

  String get labelSettingsMinimizeOnCloseExplanation => Intl.message(
      "When closing the window, the app will be minimized instead of exited",
      desc: "Explains what the 'minimize on close' setting does",
      name: "labelSettingsMinimizeOnCloseExplanation");

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: labelSettingsWindowBehaviourTitle,
      showDivider: false,
      children: [
        BooleanPreferenceToggle(
          preference: preferences.minimizeOnClose,
          title: labelSettingsMinimizeOnCloseToggle,
          description: labelSettingsMinimizeOnCloseExplanation,
        )
      ],
    );
  }
}
