import 'package:flutter/material.dart' as material;
import 'package:flutter/semantics.dart';
import 'package:flutter/material.dart' hide IconButton, Tooltip;
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/atoms/icon_button.dart' as ig;
import 'package:tiamat/atoms/icon_button.dart' as tiamat_button;
import 'package:tiamat/atoms/circle_button.dart' as tiamat_circle;
import 'package:tiamat/atoms/icon_toggle.dart' as tiamat_toggle;
import 'package:tiamat/tiamat.dart' show Tooltip;

/// The four button atoms carry most of the app's tooltips - roughly 201
/// `tooltip:` parameters route through them - so they are where the migration to
/// the house component actually lands.
///
/// `CircleButton` was missed by the first pass, which said "the three button
/// atoms" and meant it. It has the identical shape, so it is covered by the same
/// parameterised cases rather than by a special one - which is the point of
/// keeping these as a map: a fifth atom is a map entry, not a new test.
///
/// The risk this file guards is accessibility. Each atom announces its label
/// through its own Semantics wrapper, and the label is
/// `semanticLabel ?? tooltip ?? default` - the same string the tooltip shows. So
/// the tooltip must stay silent, or a screen reader says it twice. Two of the
/// three already did that; `intergalactic`'s did not, and was double-announcing
/// before this change.
///
/// See DECISIONS.md 2026-08-18, D4 and D7.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      material.MaterialApp(
        home: material.Scaffold(body: material.Center(child: child)),
      ),
    );
  }

  final atoms = <String, Widget>{
    'tiamat IconButton': const tiamat_button.IconButton(
      icon: Icons.mic_off,
      tooltip: 'Mute',
    ),
    'tiamat IconToggle': const tiamat_toggle.IconToggle(
      icon: Icons.mic_off,
      tooltip: 'Mute',
    ),
    'intergalactic IconButton': const ig.IconButton(
      icon: Icons.mic_off,
      tooltip: 'Mute',
    ),
    'tiamat CircleButton': const tiamat_circle.CircleButton(
      icon: Icons.mic_off,
      tooltip: 'Mute',
    ),
  };

  for (final entry in atoms.entries) {
    testWidgets('${entry.key} uses the house tooltip, not Material', (
      tester,
    ) async {
      await pump(tester, entry.value);

      expect(find.byType(Tooltip), findsOneWidget);
      expect(
        find.byType(material.Tooltip),
        findsNothing,
        reason:
            '${entry.key} still wraps its child in a Material tooltip, which '
            'cannot be placed to the side and keeps the OverlayPortal path',
      );
    });

    testWidgets('${entry.key} announces its label exactly once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, entry.value);

      // Walk the whole semantics tree rather than one node. The tooltip is the
      // outermost widget and emits no semantics of its own, so asking
      // getSemantics for its node returns an ancestor and tells you nothing.
      final labels = <String>[];
      final tooltips = <String>[];
      void collect(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (data.label.isNotEmpty) labels.add(data.label);
        if (data.tooltip.isNotEmpty) tooltips.add(data.tooltip);
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      final root =
          tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
      collect(root);

      // The label must survive the migration...
      expect(
        labels.where((l) => l.contains('Mute')),
        hasLength(1),
        reason:
            '${entry.key} should announce "Mute" exactly once as a label; got '
            '$labels',
      );

      // ...and the tooltip must not repeat it. This is the assertion that would
      // have caught intergalactic's IconButton double-announcing.
      expect(
        tooltips.where((t) => t.contains('Mute')),
        isEmpty,
        reason:
            '${entry.key} announces "Mute" as a tooltip as well as a label, so '
            'a screen reader will say it twice; got $tooltips',
      );

      handle.dispose();
    });
  }

  final directionalAtoms = <String, Widget>{
    'tiamat IconButton': const tiamat_button.IconButton(
      icon: Icons.mic_off,
      tooltip: 'Mute',
      tooltipDirection: AxisDirection.down,
    ),
    'tiamat IconToggle': const tiamat_toggle.IconToggle(
      icon: Icons.mic_off,
      tooltip: 'Mute',
      tooltipDirection: AxisDirection.down,
    ),
    'intergalactic IconButton': const ig.IconButton(
      icon: Icons.mic_off,
      tooltip: 'Mute',
      tooltipDirection: AxisDirection.down,
    ),
    'tiamat CircleButton': const tiamat_circle.CircleButton(
      icon: Icons.mic_off,
      tooltip: 'Mute',
      tooltipDirection: AxisDirection.down,
    ),
  };

  for (final entry in directionalAtoms.entries) {
    testWidgets('${entry.key} forwards tooltipDirection', (tester) async {
      await pump(tester, entry.value);

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.preferredDirection, AxisDirection.down);
    });
  }

  for (final entry in atoms.entries) {
    testWidgets('${entry.key} defaults tooltipDirection to up', (tester) async {
      await pump(tester, entry.value);

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.preferredDirection, AxisDirection.up);
    });
  }
}
