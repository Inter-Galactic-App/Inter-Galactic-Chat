import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The previous version of this file asserted the rail used `material.Tooltip`
/// "without overlay entries". That encoded the BUG-306 workaround as the
/// requirement, so the visual regression it caused - a white tooltip sitting on
/// top of the space icons, making them hard to click - was locked in and stayed
/// green for three months.
///
/// These tests assert the *requirement* instead: the label must appear on hover,
/// and it must not cover the thing it describes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const childKey = material.ValueKey('rail-tooltip-target');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  /// Mirrors the real rail: a narrow fixed-width column on the left with the
  /// rest of the window free beside it.
  ///
  /// The width matters. `SideNavigationBar.tooltip` wraps its child in an
  /// `AspectRatio`, which forces the child to the computed size - so in an
  /// unbounded `Center` the 48x48 target becomes 600x600 and *any* tooltip
  /// placement lands inside it. Constraining the column to the rail's real
  /// width is what makes the placement assertion mean anything.
  Future<void> pumpRailTooltip(WidgetTester tester) async {
    await tester.pumpWidget(
      material.MaterialApp(
        home: material.Scaffold(
          body: material.Row(
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              material.SizedBox(
                width: 70,
                child: material.Builder(
                  builder: (context) => SideNavigationBar.tooltip(
                    'Open space',
                    const material.SizedBox(
                      key: childKey,
                      width: 48,
                      height: 48,
                    ),
                    context,
                  ),
                ),
              ),
              const material.Expanded(child: material.SizedBox()),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> hoverTarget(WidgetTester tester) async {
    // A bare PointerHoverEvent does not drive MouseTracker, so the tooltip
    // never appears. A real mouse pointer moved onto the target is what shows
    // it. (Kept from the original test - it was the one hard-won detail in it.)
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byKey(childKey)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('rail tooltip shows its label on hover', (tester) async {
    await pumpRailTooltip(tester);
    expect(find.text('Open space'), findsNothing);

    await hoverTarget(tester);

    expect(find.text('Open space'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rail tooltip does not cover the icon it describes', (
    tester,
  ) async {
    await pumpRailTooltip(tester);
    await hoverTarget(tester);

    final target = tester.getRect(find.byKey(childKey));
    final label = tester.getRect(find.text('Open space'));

    // The requirement from the owner, and the whole point of BUG-306: a rail
    // tooltip that overlaps its icon makes the icon hard to click.
    expect(
      label.overlaps(target),
      isFalse,
      reason:
          'tooltip label $label overlaps the icon $target - it must sit beside '
          'it, not on top of it',
    );

    // And specifically beside it, on the side the rail has room for.
    expect(
      label.left >= target.right,
      isTrue,
      reason: 'tooltip label should be to the right of the rail icon',
    );
  });

  testWidgets('rail tooltip is the house component, not a Material tooltip', (
    tester,
  ) async {
    await pumpRailTooltip(tester);

    expect(find.byType(tiamat.Tooltip), findsOneWidget);

    // Material's Tooltip cannot be positioned to the side at all - it offers
    // preferBelow only - so its presence here means the placement requirement
    // above cannot be met. It also puts the rail back on OverlayPortal, which
    // is the BUG-300 crash path inside the ReorderableListView both rails use.
    expect(find.byType(material.Tooltip), findsNothing);
  });
}
