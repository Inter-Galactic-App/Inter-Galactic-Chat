import 'dart:async';

import 'package:intergalactic/config/preferences/bool_preference.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class BooleanPreferenceToggle extends StatefulWidget {
  const BooleanPreferenceToggle(
      {required this.preference,
      required this.title,
      this.description,
      this.onChanged,
      super.key});
  final BoolPreference preference;
  final FutureOr<void> Function(bool)? onChanged;

  final String title;
  final String? description;

  @override
  State<BooleanPreferenceToggle> createState() =>
      _BooleanPreferenceToggleState();
}

class _BooleanPreferenceToggleState extends State<BooleanPreferenceToggle> {
  StreamSubscription<bool>? _preferenceSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToPreferenceChanges();
  }

  @override
  void didUpdateWidget(covariant BooleanPreferenceToggle oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (identical(oldWidget.preference, widget.preference)) {
      return;
    }

    _preferenceSubscription?.cancel();
    _subscribeToPreferenceChanges();
  }

  @override
  void dispose() {
    _preferenceSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToPreferenceChanges() {
    _preferenceSubscription = widget.preference.onChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsControlRow(
      title: widget.title,
      description: widget.description,
      trailing: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
        child: tiamat.Switch(
          state: widget.preference.value,
          onChanged: (value) async {
            await widget.preference.set(value);
            if (mounted) {
              setState(() {});
            }
            await widget.onChanged?.call(value);
          },
        ),
      ),
    );
  }
}

class NullableBooleanPreferenceToggle extends StatefulWidget {
  const NullableBooleanPreferenceToggle(
      {required this.preference,
      required this.title,
      this.description,
      super.key});
  final NullableBoolPreference preference;

  final String title;
  final String? description;

  @override
  State<NullableBooleanPreferenceToggle> createState() =>
      _NullableBooleanPreferenceToggleState();
}

class _NullableBooleanPreferenceToggleState
    extends State<NullableBooleanPreferenceToggle> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsControlRow(
      title: widget.title,
      description: widget.description,
      trailing: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
        child: tiamat.Switch(
          state: widget.preference.value ?? false,
          onChanged: (value) async {
            await widget.preference.set(value);
            if (mounted) {
              setState(() {});
            }
          },
        ),
      ),
    );
  }
}
