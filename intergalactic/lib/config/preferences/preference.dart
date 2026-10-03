import 'dart:async';

import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Preference<T> {
  static SharedPreferences? preferences;

  final String key;
  final T defaultValue;
  late T? Function() _getter;
  late T Function()? _defaultGetter;
  late Future<void> Function(T value) _setter;

  Stream<T> get onChanged => _controller.stream;

  StreamController<T> _controller = StreamController.broadcast();

  Preference(
    this.key, {
    required this.defaultValue,
    required T? Function() getter,
    required Future<void> Function(T value) setter,
    T Function()? defaultGetter,
  }) {
    _getter = getter;
    _setter = setter;
    _defaultGetter = defaultGetter;
  }

  /// Runs after a preference is persisted and BEFORE [set] returns, with the
  /// preference key. Installed by startup on iOS for the notification policy
  /// snapshot (S&C C3: "written in the same operation as the preference
  /// change"). A listener on [onChanged] would fire after the caller
  /// continued, which is the window the condition closes.
  static Future<void> Function(String key)? afterWrite;

  /// Runs after the whole store is cleared.
  static Future<void> Function()? afterClear;

  Future<void> set(T value) async {
    await _setter(value);
    final hook = afterWrite;
    if (hook != null) {
      try {
        await hook(key);
      } catch (_) {
        // The hook owns its own logging; a preference write never fails
        // because a derived artefact could not be written.
      }
    }
    Preferences.onSettingChangedController.add(null);
    _controller.add(value);
  }

  T get value => _getter() ?? _defaultGetter?.call() ?? defaultValue;

  @override
  bool operator ==(Object other) {
    throw Exception(
      "Do not check for equality on a preference, check the preferences value",
    );
  }

  @override
  String toString() {
    throw Exception(
      "Do not convert a preference to string, use the preferences value",
    );
  }
}
