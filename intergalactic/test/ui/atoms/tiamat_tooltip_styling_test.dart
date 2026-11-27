import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:tiamat/tiamat.dart' show Tooltip;

/// The escape hatches added 2026-09-12 so the last Material tooltip sites can
/// convert without changing how they look.
///
/// Four sites in the app style their tooltip rather than their child: one
/// shows rich content, two override the surface, one overrides the text
/// colour for legibility over live video. Without these the migration would
/// either stall on those four or silently restyle them.
///
/// The risk each case guards is the same one: an override that is accepted but
/// not applied looks exactly like a component that has no override at all,
/// because a tooltip's body is not on screen until it is shown.
void main() {
  const childKey = ValueKey('tooltip-target');

  Future<JustTheTooltip> pumpAndRead(
    WidgetTester tester,
    Tooltip subject,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: subject)),
      ),
    );
    return tester.widget<JustTheTooltip>(find.byType(JustTheTooltip));
  }

  /// Mounts the body the package would show on hover.
  ///
  /// A tooltip's content is not in the tree until it is shown, so a `find.text`
  /// against the collapsed widget finds nothing whether or not the override was
  /// threaded through - the same false-negative shape in both directions. This
  /// pumps the exact widget instance handed to the package.
  Future<void> pumpBody(WidgetTester tester, JustTheTooltip tooltip) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: tooltip.content)),
      ),
    );
  }

  testWidgets('defaults are unchanged by the new parameters', (tester) async {
    // The 52 sites that convert mechanically pass none of these, so the
    // default rendering is what almost every tooltip in the app gets.
    final tooltip = await pumpAndRead(
      tester,
      const Tooltip(
        text: 'Mute',
        child: SizedBox(key: childKey, width: 40, height: 40),
      ),
    );

    final context = tester.element(find.byKey(childKey));
    expect(
      tooltip.backgroundColor,
      Theme.of(context).colorScheme.surfaceContainerLowest,
    );

    await pumpBody(tester, tooltip);
    expect(find.text('Mute'), findsOneWidget);
  });

  testWidgets('backgroundColor overrides the house surface', (tester) async {
    final tooltip = await pumpAndRead(
      tester,
      const Tooltip(
        text: 'Mute',
        backgroundColor: Color(0xDD000000),
        child: SizedBox(key: childKey, width: 40, height: 40),
      ),
    );

    expect(tooltip.backgroundColor, const Color(0xDD000000));
  });

  testWidgets('textColor reaches the rendered body', (tester) async {
    final tooltip = await pumpAndRead(
      tester,
      const Tooltip(
        text: 'Over video',
        textColor: Color(0xFFFFFFFF),
        child: SizedBox(key: childKey, width: 40, height: 40),
      ),
    );

    // Read the PAINTED text, not the parameter: the body is built inside the
    // package's content subtree, so a value stored and never threaded through
    // would pass a widget-property check.
    await pumpBody(tester, tooltip);
    final text = tester.widget<Text>(find.text('Over video'));
    expect(text.style?.color, const Color(0xFFFFFFFF));
  });

  testWidgets('content replaces the body but not the announcement', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    final tooltip = await pumpAndRead(
      tester,
      const Tooltip(
        text: 'Reacted by 3 people',
        content: SizedBox(key: ValueKey('rich-body'), width: 10),
        child: SizedBox(key: childKey, width: 40, height: 40),
      ),
    );

    // `text` stays required precisely so this cannot be lost: a rich tooltip
    // with nothing to announce is the D7 failure in a new costume.
    // Read the node's tooltip directly: containsSemantics is deprecated, and
    // the Dart gate treats an info as fatal.
    expect(
      tester.getSemantics(find.byKey(childKey)).tooltip,
      'Reacted by 3 people',
    );
    handle.dispose();

    await pumpBody(tester, tooltip);
    expect(find.byKey(const ValueKey('rich-body')), findsOneWidget);
    expect(
      find.text('Reacted by 3 people'),
      findsNothing,
      reason: 'content replaces the rendered text',
    );
  });

  testWidgets('padding reaches the body', (tester) async {
    final tooltip = await pumpAndRead(
      tester,
      const Tooltip(
        text: 'Padded',
        padding: EdgeInsets.all(20),
        child: SizedBox(key: childKey, width: 40, height: 40),
      ),
    );

    await pumpBody(tester, tooltip);
    final padding = tester.widget<Padding>(
      find
          .ancestor(of: find.text('Padded'), matching: find.byType(Padding))
          .first,
    );
    expect(padding.padding, const EdgeInsets.all(20));
  });
}
