// The alarm for BUG-291/BUG-298 is debug-only and reports rather than throws,
// which means a change that stops it firing looks exactly like a codebase with
// no reparents in it. This provokes the real condition - a GlobalKey-keyed
// subtree reactivated inside a LayoutBuilder's callback, which runs during
// layout - and asserts the guard reports.
//
// The negative test is the load-bearing half: the same reparent BETWEEN frames
// is ordinary and must stay silent, because a guard that fires on legitimate
// reparenting would be turned off rather than fixed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/molecules/timeline_events/debug_reparent_during_layout_guard.dart';

class _Guarded extends StatefulWidget {
  const _Guarded({super.key});

  @override
  State<_Guarded> createState() => _GuardedState();
}

class _GuardedState extends State<_Guarded>
    with DebugAssertNoReparentDuringLayout {
  @override
  String get debugReparentContext => 'the guarded test widget';

  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}

/// Moves [child] between two parents, either inside a `LayoutBuilder` callback
/// (during layout) or in an ordinary rebuild (between frames).
class _Reparenter extends StatefulWidget {
  const _Reparenter({required this.child, required this.duringLayout});

  final Widget child;
  final bool duringLayout;

  @override
  State<_Reparenter> createState() => _ReparenterState();
}

class _ReparenterState extends State<_Reparenter> {
  bool wrapped = false;

  void reparent() => setState(() => wrapped = !wrapped);

  Widget _tree() => wrapped
      ? Padding(padding: EdgeInsets.zero, child: widget.child)
      : widget.child;

  @override
  Widget build(BuildContext context) {
    if (!widget.duringLayout) {
      return _tree();
    }
    // The builder runs inside _RenderLayoutBuilder.performLayout, so the
    // GlobalKey element is deactivated and reactivated while
    // rootPipelineOwner.debugDoingLayout is true - the exact condition the
    // guard exists to name.
    return LayoutBuilder(builder: (context, _) => _tree());
  }
}

Future<void> _pumpAndReparent(
  WidgetTester tester, {
  required bool duringLayout,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: _Reparenter(
        duringLayout: duringLayout,
        child: _Guarded(key: key),
      ),
    ),
  );

  tester.state<_ReparenterState>(find.byType(_Reparenter)).reparent();
  await tester.pump();
}

void main() {
  testWidgets('reports a GlobalKey-keyed reparent that happens during layout', (
    tester,
  ) async {
    await _pumpAndReparent(tester, duringLayout: true);

    final reported = tester.takeException();
    expect(
      reported,
      isFlutterError,
      reason:
          'the guard reports rather than throws, so the reparent should '
          'surface as a reported FlutterError and not as silence',
    );
    expect(
      reported.toString(),
      allOf(
        contains('reparented during layout'),
        contains('the guarded test widget'),
      ),
      reason:
          'the message must name the offending site - reconstructing it '
          'from the stack is what BUG-298 cost several wrong attributions',
    );
  });

  testWidgets('stays silent when the same reparent happens between frames', (
    tester,
  ) async {
    await _pumpAndReparent(tester, duringLayout: false);

    expect(
      tester.takeException(),
      isNull,
      reason:
          'reparenting outside layout is legal; a guard that fires here '
          'would be disabled rather than fixed',
    );
  });
}
