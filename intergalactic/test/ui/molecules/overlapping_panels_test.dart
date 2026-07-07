import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/molecules/overlapping_panels.dart';

void main() {
  testWidgets('arrow keys and escape move between mobile panels',
      (tester) async {
    final panelsKey = GlobalKey<OverlappingPanelsState>();
    final sideChanges = <RevealSide>[];

    await tester.pumpWidget(_buildPanels(
      panelsKey: panelsKey,
      onSideChange: sideChanges.add,
    ));
    await tester.pump();

    expect(panelsKey.currentState!.currentSide, RevealSide.main);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(panelsKey.currentState!.currentSide, RevealSide.left);
    expect(sideChanges.last, RevealSide.left);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(panelsKey.currentState!.currentSide, RevealSide.main);
    expect(sideChanges.last, RevealSide.main);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(panelsKey.currentState!.currentSide, RevealSide.right);
    expect(sideChanges.last, RevealSide.right);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(panelsKey.currentState!.currentSide, RevealSide.main);
    expect(sideChanges.last, RevealSide.main);
  });

  testWidgets('arrow keys do not move panels while editing text',
      (tester) async {
    final panelsKey = GlobalKey<OverlappingPanelsState>();
    const editorKey = ValueKey('panel-editor');

    await tester.pumpWidget(_buildPanels(
      panelsKey: panelsKey,
      main: const Padding(
        padding: EdgeInsets.all(24),
        child: TextField(key: editorKey),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(editorKey));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(panelsKey.currentState!.currentSide, RevealSide.main);
  });

  testWidgets('arrow keys and escape ignore another focused child',
      (tester) async {
    final panelsKey = GlobalKey<OverlappingPanelsState>();
    final otherFocus = FocusNode(debugLabel: 'other-focus');
    addTearDown(otherFocus.dispose);

    await tester.pumpWidget(_buildPanels(
      panelsKey: panelsKey,
      main: Focus(
        focusNode: otherFocus,
        child: const Center(child: Text('Focused content')),
      ),
    ));
    await tester.pump();

    otherFocus.requestFocus();
    await tester.pump();

    expect(otherFocus.hasPrimaryFocus, true);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(panelsKey.currentState!.currentSide, RevealSide.main);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(panelsKey.currentState!.currentSide, RevealSide.main);
  });

  testWidgets('panel reveal completes immediately with reduced motion',
      (tester) async {
    final panelsKey = GlobalKey<OverlappingPanelsState>();
    final sideChanges = <RevealSide>[];

    await tester.pumpWidget(_buildPanels(
      panelsKey: panelsKey,
      onSideChange: sideChanges.add,
      disableAnimations: true,
    ));
    await tester.pump();

    panelsKey.currentState!.reveal(RevealSide.left);
    await tester.pump();

    expect(panelsKey.currentState!.currentSide, RevealSide.left);
    expect(sideChanges, [RevealSide.left]);
  });
}

Widget _buildPanels({
  required GlobalKey<OverlappingPanelsState> panelsKey,
  Widget main = const Center(child: Text('Main panel')),
  ValueChanged<RevealSide>? onSideChange,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 720),
        disableAnimations: disableAnimations,
      ),
      child: Scaffold(
        body: SizedBox(
          width: 390,
          height: 720,
          child: OverlappingPanels(
            key: panelsKey,
            left: const Center(child: Text('Left panel')),
            main: main,
            right: const Center(child: Text('Right panel')),
            onSideChange: onSideChange,
          ),
        ),
      ),
    ),
  );
}
