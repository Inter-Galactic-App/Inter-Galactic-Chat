import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// The default flutter_test surface, which the expectations below are stated
/// against. Halves are 400 and 300.
const _surface = Size(800, 600);

Future<void> _openMenuAt(
  WidgetTester tester,
  Offset at, {
  int itemCount = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: ContextMenu(
          modal: true,
          items: [
            for (var i = 0; i < itemCount; i++)
              ContextMenuItem(text: 'Item $i'),
          ],
          // Fills the surface so a tap anywhere lands on the menu's trigger and
          // the recorded pointer position is exactly `at`.
          child: const SizedBox.expand(child: ColoredBox(color: Colors.grey)),
        ),
      ),
    ),
  );

  await tester.tapAt(at);
  await tester.pumpAndSettle();
}

/// The box the layout delegate positions.
///
/// Deliberately the delegate's direct child rather than the SizeTransition
/// inside it: SizeTransition renders an Align that expands to the full incoming
/// width, so measuring it would measure the screen, not the menu.
Finder get _menuBox => find.byType(IntrinsicWidth);

void main() {
  testWidgets('never builds the menu offstage to measure it', (tester) async {
    // The regression guard for BUG-298. The old implementation built the menu
    // once inside an Offstage carrying a GlobalKey purely to read its size,
    // then rebuilt it without the key in its final position. That add/remove of
    // a GlobalKey-keyed subtree is the reparent that crashed layout, so the
    // measuring copy must never exist.
    await _openMenuAt(tester, const Offset(100, 100));

    expect(find.text('Item 0'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Item 0'), matching: find.byType(Offstage)),
      findsNothing,
      reason: 'the menu was measured by building it offstage - BUG-298',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('anchors to the pointer when opened in the top-left half', (
    tester,
  ) async {
    const at = Offset(100, 100);

    await _openMenuAt(tester, at);

    final topLeft = tester.getTopLeft(_menuBox);
    expect(topLeft.dx, moreOrLessEquals(at.dx, epsilon: 0.5));
    expect(topLeft.dy, moreOrLessEquals(at.dy, epsilon: 0.5));
  });

  testWidgets('flips so the menu grows away from a bottom-right pointer', (
    tester,
  ) async {
    // Past both halves, so the menu opens up and to the left and its
    // bottom-right corner sits on the pointer.
    const at = Offset(700, 500);

    await _openMenuAt(tester, at);

    final bottomRight = tester.getBottomRight(_menuBox);
    expect(bottomRight.dx, moreOrLessEquals(at.dx, epsilon: 0.5));
    expect(bottomRight.dy, moreOrLessEquals(at.dy, epsilon: 0.5));
  });

  testWidgets('clamps a menu too tall to fit below the pointer', (
    tester,
  ) async {
    // Just above the halfway line, so the menu does not flip, but with more
    // items than fit in the space underneath. Flipping cannot save this one;
    // only the clamp keeps it on screen.
    const anchorY = 299.0;
    await _openMenuAt(tester, const Offset(100, anchorY), itemCount: 10);

    final rect = tester.getRect(_menuBox);

    // Precondition: if item heights ever change so the menu *would* fit below
    // the anchor, this test silently stops testing the clamp. Fail loudly
    // instead.
    expect(
      rect.height,
      greaterThan(_surface.height - anchorY),
      reason: 'menu now fits below the anchor - the clamp is untested',
    );

    expect(rect.top, greaterThanOrEqualTo(-0.5));
    expect(rect.bottom, lessThanOrEqualTo(_surface.height + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens without a measuring frame', (tester) async {
    // Previously the menu needed a post-frame callback to measure itself before
    // it could be positioned, so it was absent for an extra frame. It should
    // now be laid out as soon as the overlay entry builds.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
          body: ContextMenu(
            modal: true,
            items: const [ContextMenuItem(text: 'Copy')],
            child: const Text('Open menu'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open menu'));
    // One pump runs the post-frame callback that inserts the overlay entry, the
    // second builds it. No third pump for a measure pass.
    await tester.pump();
    await tester.pump();

    expect(find.text('Copy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('anchors to the pointer from inside a nested overlay', (
    tester,
  ) async {
    // The anchor is a global `PointerEvent.position` consumed by the layout
    // delegate as a local offset, so it is only correct in an overlay whose box
    // starts at the view origin. `Overlay.maybeOf` defaults to the *nearest*
    // overlay, so before `rootOverlay: true` a ContextMenu under any nested
    // Navigator/Overlay anchored at `nestedOrigin + pointer`.
    const nestedOrigin = Offset(120, 90);
    const at = Offset(300, 200);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
          body: Padding(
            // Displaces the nested overlay from the view origin. Without it the
            // two coordinate spaces coincide and the bug is invisible.
            padding: EdgeInsets.only(
              left: nestedOrigin.dx,
              top: nestedOrigin.dy,
            ),
            child: Navigator(
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (context) => ContextMenu(
                  modal: true,
                  items: const [ContextMenuItem(text: 'Item 0')],
                  child: const SizedBox.expand(
                    child: ColoredBox(color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(at);
    await tester.pumpAndSettle();

    expect(find.text('Item 0'), findsOneWidget);
    final topLeft = tester.getTopLeft(_menuBox);
    expect(
      topLeft.dx,
      moreOrLessEquals(at.dx, epsilon: 0.5),
      reason: 'menu was placed in a nested overlay\'s coordinate space',
    );
    expect(
      topLeft.dy,
      moreOrLessEquals(at.dy, epsilon: 0.5),
      reason: 'menu was placed in a nested overlay\'s coordinate space',
    );
    expect(tester.takeException(), isNull);
  });

  test('surface assumption the expectations above are stated against', () {
    expect(_surface, const Size(800, 600));
  });
}
