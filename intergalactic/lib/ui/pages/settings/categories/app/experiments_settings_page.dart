import 'package:flutter/material.dart';

import 'package:intergalactic/config/experiments.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ExperimentsSettingsPage extends StatefulWidget {
  const ExperimentsSettingsPage({super.key});

  @override
  State<ExperimentsSettingsPage> createState() =>
      _ExperimentsSettingsPageState();
}

class _ExperimentsSettingsPageState extends State<ExperimentsSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final experiments = Experiments.visibleFor(
      developerMode: preferences.developerMode.value,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: tiamat.Text.label(
            "These features are still under development, and may contain bugs or security issues. Enable at your own risk",
          ),
        ),
        SettingsSection(
          title: "Experiments",
          showDivider: false,
          children: [
            for (final experiment in experiments)
              _ExperimentToggle(
                experiment: experiment,
                value: preferences.isExperimentEnabled(experiment.id),
                onChanged: (value) async {
                  await preferences.setExperimentEnabled(
                    experiment.id,
                    value,
                  );

                  if (context.mounted) {
                    setState(() {});
                  }
                },
              ),
          ],
        ),
        if (experiments.any(
          (experiment) => experiment.requiresRestart,
        ))
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: tiamat.Text.error(
              "You must restart the app for changes to take effect",
            ),
          ),
      ],
    );
  }
}

class _ExperimentToggle extends StatelessWidget {
  const _ExperimentToggle({
    required this.experiment,
    required this.value,
    required this.onChanged,
  });

  final ExperimentDefinition experiment;
  final bool value;
  final Future<void> Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    Future<void> toggle() => onChanged(!value);

    return SettingsControlRow(
      title: experiment.label,
      description: experiment.description,
      semanticValue: settingsToggleStateLabel(value),
      toggled: value,
      semanticOnTapHint: "Toggle experiment",
      onActivate: toggle,
      excludeChildSemantics: true,
      trailing: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
        child: SettingsSwitchStateLabel(
          value: value,
          child: ExcludeFocus(
            child: tiamat.Switch(
              state: value,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }
}
