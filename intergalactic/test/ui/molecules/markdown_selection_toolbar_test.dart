import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/molecules/markdown_selection_toolbar.dart';

void main() {
  for (final width in [1000.0, 320.0]) {
    for (final withFormatting in [true, false]) {
      testWidgets('toolbar clickable at $width, formatting $withFormatting', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(ContextMenuController.removeAny);
        var clicks = 0;
        final menu = ContextMenuController();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => Overlay.wrap(child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => menu.show(
                    context: context,
                    contextMenuBuilder: (_) => MarkdownSelectionToolbar(
                      anchors: TextSelectionToolbarAnchors(
                        primaryAnchor: Offset(width / 2, 550),
                      ),
                      formattingActions: [
                        if (withFormatting)
                          for (var i = 0; i < 6; i++)
                            MarkdownSelectionToolbarAction(
                              icon: Icons.format_bold,
                              label: 'Format $i',
                              onPressed: () => clicks++,
                            ),
                      ],
                      standardActions: [
                        for (var i = 0; i < 4; i++)
                          MarkdownSelectionToolbarAction(
                            icon: Icons.copy,
                            label: 'Edit $i',
                            onPressed: () => clicks++,
                          ),
                      ],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: Offset.zero);
        for (final icon in [Icons.format_bold, Icons.copy]) {
          final buttons = find.byIcon(icon);
          for (var i = 0; i < buttons.evaluate().length; i++) {
            await pointer.moveTo(tester.getCenter(buttons.at(i)));
            await tester.pumpAndSettle(
              const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 3),
            );
            expect(tester.takeException(), isNull);
            await tester.tap(buttons.at(i));
            await tester.pumpAndSettle();
          }
        }
        await pointer.removePointer();
        expect(clicks, withFormatting ? 10 : 4);
        menu.remove();
        await tester.pumpAndSettle();
        expect(find.byType(MarkdownSelectionToolbar), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'right-click text field menu survives hover and executes action',
    (tester) async {
      final controller = TextEditingController(text: 'Sample message');
      addTearDown(controller.dispose);
      addTearDown(ContextMenuController.removeAny);
      var clicks = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => Overlay.wrap(child: child!),
          home: Scaffold(
            body: TextField(
              controller: controller,
              contextMenuBuilder: (context, editable) =>
                  MarkdownSelectionToolbar(
                    anchors: editable.contextMenuAnchors,
                    standardActions: [
                      MarkdownSelectionToolbarAction(
                        icon: Icons.copy,
                        label: 'Copy',
                        onPressed: () {
                          clicks++;
                          editable.hideToolbar();
                        },
                      ),
                    ],
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(find.byIcon(Icons.copy), findsOneWidget);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(tester.getCenter(find.byIcon(Icons.copy)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.copy));
      await pointer.removePointer();
      await tester.pumpAndSettle();
      expect(clicks, 1);
      expect(find.byType(MarkdownSelectionToolbar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
