import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences/bool_preference.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';

void main() {
  testWidgets('SettingsControlRow exposes toggle state and keyboard activation',
      (tester) async {
    var enabled = false;
    var activations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: SettingsControlRow(
                title: 'Show labels',
                description: 'Display On and Off text beside toggles.',
                semanticValue: enabled ? 'On' : 'Off',
                toggled: enabled,
                semanticOnTapHint: 'Toggle setting',
                excludeChildSemantics: true,
                onActivate: () {
                  setState(() {
                    enabled = !enabled;
                    activations++;
                  });
                },
                trailing: ExcludeFocus(
                  child: Switch(
                    value: enabled,
                    onChanged: (value) {
                      setState(() {
                        enabled = value;
                      });
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    final semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((widget) => widget.properties.label == 'Show labels');

    expect(semantics.properties.value, 'Off');
    expect(semantics.properties.toggled, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(enabled, isTrue);
    expect(activations, 1);

    final updatedSemantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((widget) => widget.properties.label == 'Show labels');

    expect(updatedSemantics.properties.value, 'On');
    expect(updatedSemantics.properties.toggled, isTrue);
  });

  testWidgets('BooleanPreferenceToggle exposes pending value before write ends',
      (tester) async {
    final preference = _DelayedBoolPreference(initial: false);
    addTearDown(preference.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BooleanPreferenceToggle(
            preference: preference,
            title: 'Delayed setting',
            description: 'Updates after a delayed write.',
          ),
        ),
      ),
    );

    var semantics = _rowSemantics(tester, 'Delayed setting');
    expect(semantics.properties.value, 'Off');
    expect(semantics.properties.toggled, isFalse);

    await tester.tap(find.text('Delayed setting'));
    await tester.pump();

    expect(preference.setCalls, 1);
    expect(preference.value, isFalse);
    semantics = _rowSemantics(tester, 'Delayed setting');
    expect(semantics.properties.value, 'On');
    expect(semantics.properties.toggled, isTrue);
    expect(semantics.properties.enabled, isFalse);

    await tester.tap(find.text('Delayed setting'));
    await tester.pump();

    expect(preference.setCalls, 1);

    preference.completeWrite();
    await tester.pump();
    await tester.pump();

    expect(preference.value, isTrue);
    semantics = _rowSemantics(tester, 'Delayed setting');
    expect(semantics.properties.value, 'On');
    expect(semantics.properties.toggled, isTrue);
    expect(semantics.properties.enabled, isTrue);
  });

  testWidgets(
      'NullableBooleanPreferenceToggle exposes pending value before write ends',
      (tester) async {
    final preference = _DelayedNullableBoolPreference(initial: null);
    addTearDown(preference.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NullableBooleanPreferenceToggle(
            preference: preference,
            title: 'Delayed nullable setting',
            description: 'Updates after a delayed nullable write.',
          ),
        ),
      ),
    );

    var semantics = _rowSemantics(tester, 'Delayed nullable setting');
    expect(semantics.properties.value, 'Off');
    expect(semantics.properties.toggled, isFalse);

    await tester.tap(find.text('Delayed nullable setting'));
    await tester.pump();

    expect(preference.setCalls, 1);
    expect(preference.value, isNull);
    semantics = _rowSemantics(tester, 'Delayed nullable setting');
    expect(semantics.properties.value, 'On');
    expect(semantics.properties.toggled, isTrue);
    expect(semantics.properties.enabled, isFalse);

    await tester.tap(find.text('Delayed nullable setting'));
    await tester.pump();

    expect(preference.setCalls, 1);

    preference.completeWrite();
    await tester.pump();
    await tester.pump();

    expect(preference.value, isTrue);
    semantics = _rowSemantics(tester, 'Delayed nullable setting');
    expect(semantics.properties.value, 'On');
    expect(semantics.properties.toggled, isTrue);
    expect(semantics.properties.enabled, isTrue);
  });
}

Semantics _rowSemantics(WidgetTester tester, String label) {
  return tester
      .widgetList<Semantics>(find.byType(Semantics))
      .singleWhere((widget) => widget.properties.label == label);
}

class _DelayedBoolPreference extends BoolPreference {
  _DelayedBoolPreference({required bool initial})
      : _value = initial,
        super('test.delayed_toggle', defaultValue: initial);

  final _controller = StreamController<bool>.broadcast();
  Completer<void>? _pendingWrite;
  bool _value;
  int setCalls = 0;

  @override
  Stream<bool> get onChanged => _controller.stream;

  @override
  bool get value => _value;

  @override
  Future<void> set(bool value) {
    setCalls++;
    final completer = Completer<void>();
    _pendingWrite = completer;
    return completer.future.then((_) {
      _value = value;
      _controller.add(value);
    });
  }

  void completeWrite() {
    final pendingWrite = _pendingWrite;
    if (pendingWrite == null || pendingWrite.isCompleted) {
      return;
    }
    pendingWrite.complete();
  }

  Future<void> dispose() => _controller.close();
}

class _DelayedNullableBoolPreference extends NullableBoolPreference {
  _DelayedNullableBoolPreference({required bool? initial})
      : _value = initial,
        super('test.delayed_nullable_toggle', defaultValue: initial);

  final _controller = StreamController<bool?>.broadcast();
  Completer<void>? _pendingWrite;
  bool? _value;
  int setCalls = 0;

  @override
  Stream<bool?> get onChanged => _controller.stream;

  @override
  bool? get value => _value;

  @override
  Future<void> set(bool? value) {
    setCalls++;
    final completer = Completer<void>();
    _pendingWrite = completer;
    return completer.future.then((_) {
      _value = value;
      _controller.add(value);
    });
  }

  void completeWrite() {
    final pendingWrite = _pendingWrite;
    if (pendingWrite == null || pendingWrite.isCompleted) {
      return;
    }
    pendingWrite.complete();
  }

  Future<void> dispose() => _controller.close();
}
