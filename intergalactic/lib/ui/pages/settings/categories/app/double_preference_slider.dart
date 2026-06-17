import 'package:intergalactic/config/preferences/double_preference.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class DoublePreferenceSlider extends StatefulWidget {
  const DoublePreferenceSlider(
      {required this.preference,
      required this.min,
      required this.max,
      required this.title,
      this.units,
      this.description,
      this.numDecimals = 1,
      this.requiresConfirmationButton = false,
      this.onChanged,
      super.key});

  final DoublePreference preference;
  final Function(double)? onChanged;
  final String? units;

  final double min;
  final double max;
  final bool requiresConfirmationButton;
  final int numDecimals;
  final String title;
  final String? description;

  @override
  State<DoublePreferenceSlider> createState() => _DoublePreferenceSliderState();
}

class _DoublePreferenceSliderState extends State<DoublePreferenceSlider> {
  late double value;

  @override
  void initState() {
    value = widget.preference.value;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsControlRow(
      title: widget.title,
      description: widget.description,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: tiamat.Text.labelLow(
              "${value.toStringAsFixed(widget.numDecimals)}${widget.units ?? ""}",
            ),
          ),
          Expanded(
            child: tiamat.Slider(
              value: value,
              min: widget.min,
              max: widget.max,
              onChanged: (newValue) {
                var strValue = newValue.toStringAsFixed(widget.numDecimals);
                var finalValue = double.parse(strValue);
                setState(() {
                  value = finalValue;
                });
              },
              onChangeEnd: widget.requiresConfirmationButton
                  ? null
                  : (newValue) {
                      final strValue =
                          newValue.toStringAsFixed(widget.numDecimals);
                      final finalValue = double.parse(strValue);
                      setState(() {
                        value = finalValue;
                      });
                      widget.preference.set(finalValue);
                      widget.onChanged?.call(finalValue);
                    },
            ),
          ),
          if (widget.requiresConfirmationButton)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 0, 0),
              child: tiamat.Button.secondary(
                text: CommonStrings.promptApply,
                onTap: () {
                  widget.preference.set(value);
                  widget.onChanged?.call(value);
                },
              ),
            )
        ],
      ),
    );
  }
}
