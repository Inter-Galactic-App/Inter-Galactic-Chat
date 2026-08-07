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
  bool? _pendingValue;

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

  Future<void> _setValue(bool value) async {
    if (mounted) {
      setState(() {
        _pendingValue = value;
      });
    } else {
      _pendingValue = value;
    }
    try {
      await widget.preference.set(value);
      await widget.onChanged?.call(value);
    } finally {
      if (mounted) {
        setState(() {
          if (_pendingValue == value) {
            _pendingValue = null;
          }
        });
      }
    }
  }

  void _toggleValue() {
    if (_pendingValue != null) {
      return;
    }
    unawaited(_setValue(!(_pendingValue ?? widget.preference.value)));
  }

  @override
  Widget build(BuildContext context) {
    final value = _pendingValue ?? widget.preference.value;

    return SettingsControlRow(
      title: widget.title,
      description: widget.description,
      semanticValue: settingsToggleStateLabel(value),
      toggled: value,
      semanticOnTapHint: "Toggle setting",
      onActivate: _toggleValue,
      enabled: _pendingValue == null,
      excludeChildSemantics: true,
      trailing: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
        child: SettingsSwitchStateLabel(
          value: value,
          child: ExcludeFocus(
            child: tiamat.Switch(
              state: value,
              onChanged: _pendingValue == null
                  ? (value) {
                      unawaited(_setValue(value));
                    }
                  : null,
            ),
          ),
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
  bool? _pendingValue;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _setValue(bool value) async {
    if (mounted) {
      setState(() {
        _pendingValue = value;
      });
    } else {
      _pendingValue = value;
    }
    try {
      await widget.preference.set(value);
    } finally {
      if (mounted) {
        setState(() {
          if (_pendingValue == value) {
            _pendingValue = null;
          }
        });
      }
    }
  }

  void _toggleValue() {
    if (_pendingValue != null) {
      return;
    }
    unawaited(_setValue(!(_pendingValue ?? widget.preference.value ?? false)));
  }

  @override
  Widget build(BuildContext context) {
    final value = _pendingValue ?? widget.preference.value ?? false;

    return SettingsControlRow(
      title: widget.title,
      description: widget.description,
      semanticValue: settingsToggleStateLabel(value),
      toggled: value,
      semanticOnTapHint: "Toggle setting",
      onActivate: _toggleValue,
      enabled: _pendingValue == null,
      excludeChildSemantics: true,
      trailing: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
        child: SettingsSwitchStateLabel(
          value: value,
          child: ExcludeFocus(
            child: tiamat.Switch(
              state: value,
              onChanged: _pendingValue == null
                  ? (value) {
                      unawaited(_setValue(value));
                    }
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
