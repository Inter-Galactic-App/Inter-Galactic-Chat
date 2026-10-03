import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/atoms/space_icon.dart';
import 'package:intergalactic/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import '../../pages/main/main_page_test_harness.dart';

/// BUG-300, guarded where the defect actually lives: in the COMBINATION.
///
/// `side_navigation_bar_tooltip_test.dart` already asserts the rail uses
/// `tiamat.Tooltip` and not `material.Tooltip`. It exercises
/// `SideNavigationBar.tooltip` in ISOLATION though - one target in a 70px
/// column - and the crash is not a property of the helper on its own. It needs
/// all three: a `ReorderableListView`, the `GlobalKey` reparenting it does
/// mid-layout, and a tooltip built on `OverlayPortal`. BUG-300's own history is
/// the argument for testing the combination: the reparent was happening and was
/// HARMLESS until `a988c91d` swapped the rail tooltip to Material's, and only
/// then did `_OverlayPortalElement.activate` become a crash.
///
/// So this pumps the real rail with its space list populated, which is what
/// puts `SpaceIcon` - and the tooltip it routes through - inside the
/// `ReorderableListView` that reparents.
///
/// WHAT THIS CANNOT DO, so it is not mistaken for DEBUG's evidence: a widget
/// test cannot show that the reparent stopped. It guards the tooltip TYPE, the
/// thing that makes the reparent fatal rather than harmless. "Nothing crashed"
/// and "the reparent stopped" are different claims, and BUG-300's entry is
/// explicit that the clean owner capture was taken with
/// `debugPrintGlobalKeyedWidgetLifecycle` OFF. The two device runs on that bug
/// remain DEBUG's and are not replaced by this.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  tearDown(() async {
    await globals.preferences.layoutOverride.set(null);
  });

  Future<FakeHarnessClient> pumpPopulatedRail(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = FakeHarnessClient(
      identifier: 'client-1',
      self: FakeHarnessProfile('@self:example.org'),
    );
    addTearDown(client.dispose);

    for (var i = 0; i < 3; i++) {
      final space = FakeHarnessSpace(
        identifier: '!space-$i:example.org',
        displayName: 'Space $i',
      );
      addTearDown(space.dispose);
      client.addSpace(space);
    }

    final clientManager = ClientManager();
    clientManager.addClient(client);

    final previousGlobal = globals.clientManager;
    globals.clientManager = clientManager;
    addTearDown(() => globals.clientManager = previousGlobal);

    await tester.pumpWidget(
      Provider<ClientManager>.value(
        value: clientManager,
        child: material.MaterialApp(
          theme: material.ThemeData.light().copyWith(
            extensions: const <material.ThemeExtension<dynamic>>[
              ThemeSettings(),
            ],
          ),
          home: const material.Scaffold(body: SideNavigationBar()),
        ),
      ),
    );
    await tester.pump();

    return client;
  }

  Finder inRail(Finder matching) =>
      find.descendant(of: find.byType(SideNavigationBar), matching: matching);

  testWidgets('the space rail actually has items to reparent', (tester) async {
    // THE VACUITY GUARD, and the reason the isolated test was not enough on its
    // own. Every assertion below is "there is no material.Tooltip here" - which
    // an empty rail satisfies perfectly. If this fails, the others are proving
    // nothing and are not to be read as green.
    //
    // Load-bearing, not ceremony. Mutation m2 (itemCount zeroed) shows the
    // three type assertions below - no Material tooltip, no OverlayPortal,
    // house tooltip present - ALL PASS over an empty rail. They cannot
    // distinguish "no Material tooltip because the rail is clean" from "no
    // Material tooltip because there is no rail". This test is the only thing
    // standing between that suite and a green run over nothing. Do not remove
    // it.
    await pumpPopulatedRail(tester);

    expect(
      inRail(find.byType(material.ReorderableListView)),
      findsWidgets,
      reason: 'the rail is not building its reorderable list at all',
    );
    expect(
      inRail(find.byType(SpaceIcon)),
      findsNWidgets(3),
      reason:
          'the space list is empty, so nothing is inside the ReorderableListView '
          'and the tooltip assertions below are vacuous',
    );
  });

  testWidgets('the populated rail contains no Material tooltip', (
    tester,
  ) async {
    await pumpPopulatedRail(tester);

    expect(
      inRail(find.byType(material.Tooltip)),
      findsNothing,
      reason:
          'a Material tooltip inside the rail puts SpaceIcon back on '
          'OverlayPortal, which is what turned the ReorderableListView reparent '
          'from harmless into the BUG-300 crash',
    );
  });

  testWidgets('the populated rail contains no OverlayPortal', (tester) async {
    // One step closer to the crash than the widget type: OverlayPortal is the
    // mechanism, material.Tooltip merely the way it got in. Asserting the
    // mechanism catches any OTHER widget that would reintroduce it.
    await pumpPopulatedRail(tester);

    expect(
      inRail(find.byType(OverlayPortal)),
      findsNothing,
      reason:
          'the BUG-300 stack is _OverlayPortalElement.activate -> '
          '_OverlayEntryLocation._activate -> _RenderTheater._addDeferredChild. '
          'Nothing in a reorderable rail may build an OverlayPortal',
    );
  });

  testWidgets('the rail still labels its icons with the house tooltip', (
    tester,
  ) async {
    // The other half of the vacuity problem: a rail that dropped tooltips
    // entirely would satisfy both assertions above while losing the labels
    // BUG-306 was filed about. The previous version of the isolated test
    // encoded the BUG-306 workaround as its requirement and stayed green
    // through a three-month visual regression; this is the same trap one level
    // up.
    await pumpPopulatedRail(tester);

    expect(inRail(find.byType(tiamat.Tooltip)), findsWidgets);
  });
}
