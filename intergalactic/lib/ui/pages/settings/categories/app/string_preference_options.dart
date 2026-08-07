import 'package:intergalactic/config/preferences/string_preference.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class StringPreferenceOptionsPicker extends StatefulWidget {
  const StringPreferenceOptionsPicker(
      {required this.preference,
      required this.title,
      this.description,
      this.onChanged,
      this.optionLabelBuilder,
      required this.options,
      super.key});

  final StringPreference preference;
  final ValueChanged<String>? onChanged;
  final String Function(String option)? optionLabelBuilder;

  final String title;
  final String? description;
  final List<String> options;

  @override
  State<StringPreferenceOptionsPicker> createState() =>
      _StringPreferenceOptionsPickerState();
}

class _StringPreferenceOptionsPickerState
    extends State<StringPreferenceOptionsPicker> {
  @override
  Widget build(BuildContext context) {
    final hasOptions = widget.options.isNotEmpty;
    final selectedValue =
        hasOptions && widget.options.contains(widget.preference.value)
            ? widget.preference.value
            : hasOptions
                ? widget.options.first
                : null;

    return SettingsControlRow(
      title: widget.title,
      description: widget.description,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, minWidth: 180),
        child: !hasOptions
            ? tiamat.Text.labelLow("No options available")
            : tiamat.DropdownSelector(
                color: ColorScheme.of(context).surfaceContainer,
                items: widget.options,
                itemBuilder: (item) {
                  return tiamat.Text(
                    widget.optionLabelBuilder?.call(item) ?? item,
                  );
                },
                onItemSelected: (item) {
                  setState(() {
                    if (item != null) {
                      widget.preference.set(item);
                      widget.onChanged?.call(item);
                    }
                  });
                },
                value: selectedValue!,
              ),
      ),
    );
  }
}
