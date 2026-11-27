import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' show Tooltip;

/// The house tooltip announces nothing on its own - `just_the_tooltip` contains
/// no `Semantics` node anywhere and sets `excludeFromSemantics: true` on its own
/// gesture detector. Material `Tooltip` announces by default.
///
/// Most tooltips in this app were added *for* accessibility, so migrating them
/// to the house component without a semantics node would silently delete the
/// thing they exist for. These tests hold that line. See DECISIONS.md
/// 2026-08-18, D7.
///
/// Note for anyone extending these: `Semantics(tooltip: ...)` sets the *tooltip*
/// property, not the label, so `find.bySemanticsLabel` does not see it. Assert
/// on the node with `containsSemantics(tooltip: ...)`.
void main() {
  const childKey = ValueKey('tooltip-target');

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('announces its message by default', (tester) async {
    final handle = tester.ensureSemantics();

    await pump(
      tester,
      const Tooltip(
        text: 'Mute microphone',
        child: SizedBox(key: childKey, width: 40, height: 40),
      ),
    );

    expect(
      tester.getSemantics(find.byKey(childKey)),
      containsSemantics(tooltip: 'Mute microphone'),
      reason: 'the tooltip message must reach a screen reader',
    );

    handle.dispose();
  });

  testWidgets('matches Material Tooltip, which announces the same way', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await pump(
      tester,
      const material.Tooltip(
        message: 'Mute microphone',
        child: SizedBox(key: childKey, width: 40, height: 40),
      ),
    );

    // Parity check. If this fails, Material changed how it announces and the
    // house component should be re-checked against it rather than assumed
    // equivalent.
    expect(
      tester.getSemantics(find.byKey(childKey)),
      containsSemantics(tooltip: 'Mute microphone'),
    );

    handle.dispose();
  });

  testWidgets('excludeFromSemantics silences the announcement', (tester) async {
    final handle = tester.ensureSemantics();

    await pump(
      tester,
      const Tooltip(
        text: 'Open space',
        excludeFromSemantics: true,
        child: SizedBox(key: childKey, width: 40, height: 40),
      ),
    );

    // What both rails pass: `SpaceIcon` already announces the same string
    // through AccessibleInteractiveRegion, and without this a reader says it
    // twice.
    expect(
      tester.getSemantics(find.byKey(childKey)),
      isNot(containsSemantics(tooltip: 'Open space')),
    );

    handle.dispose();
  });

  testWidgets('an empty message produces no tooltip semantics', (tester) async {
    final handle = tester.ensureSemantics();

    await pump(
      tester,
      const Tooltip(
        text: '',
        child: SizedBox(key: childKey, width: 40, height: 40),
      ),
    );

    // `SemanticsNode.tooltip` defaults to the empty string rather than null, so
    // "no tooltip announced" *is* `tooltip: ''`. Asserting `isNot` here would
    // pass against any node and prove nothing.
    expect(
      tester.getSemantics(find.byKey(childKey)),
      containsSemantics(tooltip: ''),
    );
    expect(tester.takeException(), isNull);

    handle.dispose();
  });
}
