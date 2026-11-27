import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';

void main() {
  testWidgets("exposes button semantics and tap action", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccessibleInteractiveRegion(
            semanticLabel: "Favorites",
            semanticOnTapHint: "Open favorites",
            onActivate: () {},
            child: const Text("Favorites"),
          ),
        ),
      ),
    );

    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == "Favorites",
      ),
    );

    expect(semantics.properties.label, "Favorites");
    expect(semantics.properties.button, isTrue);
    expect(semantics.properties.hintOverrides?.onTapHint, "Open favorites");
    expect(semantics.properties.onTap, isNotNull);
  });

  testWidgets("keyboard activation triggers the region action", (tester) async {
    var activations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccessibleInteractiveRegion(
            semanticLabel: "Favorites",
            semanticOnTapHint: "Open favorites",
            onActivate: () => activations += 1,
            child: const Text("Favorites"),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(activations, 2);
  });

  testWidgets("exposes non-activatable selected expanded and disabled states",
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AccessibleInteractiveRegion(
            semanticLabel: "Thread details",
            semanticValue: "Collapsed",
            selected: true,
            expanded: false,
            enabled: false,
            child: Text("Thread details"),
          ),
        ),
      ),
    );

    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == "Thread details",
      ),
    );

    expect(semantics.properties.selected, isTrue);
    expect(semantics.properties.expanded, isFalse);
    expect(semantics.properties.enabled, isFalse);
    expect(semantics.properties.value, "Collapsed");
    expect(semantics.properties.onTap, isNull);
  });

  testWidgets("uses larger target tokens for accessible navigation",
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: const Scaffold(
            body: AccessibleInteractiveRegion(
              semanticLabel: "Tiny action",
              child: SizedBox(width: 8, height: 8),
            ),
          ),
        ),
      ),
    );

    final constrainedBox = tester.widget<ConstrainedBox>(
      find.descendant(
        of: find.byType(AccessibleInteractiveRegion),
        matching: find.byType(ConstrainedBox),
      ),
    );

    expect(constrainedBox.constraints.minWidth, 48);
    expect(constrainedBox.constraints.minHeight, 48);
  });

  testWidgets("shows opt-in persistent action label for accessible navigation",
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccessibleInteractiveRegion(
            semanticLabel: "Add attachment",
            persistentLabel: "Attach",
            onActivate: () {},
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );

    expect(find.text("Attach"), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Scaffold(
            body: AccessibleInteractiveRegion(
              semanticLabel: "Add attachment",
              persistentLabel: "Attach",
              onActivate: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );

    expect(find.text("Attach"), findsOneWidget);
  });

  testWidgets("persistent action label shares the activation hit target",
      (tester) async {
    var activations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Scaffold(
            body: Center(
              child: AccessibleInteractiveRegion(
                semanticLabel: "Add attachment",
                persistentLabel: "Attach",
                onActivate: () => activations += 1,
                child: const SizedBox(width: 24, height: 24),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text("Attach"));

    expect(activations, 1);
  });

  testWidgets("nested child tap handler is not double-activated",
      (tester) async {
    var childActivations = 0;
    var regionActivations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Scaffold(
            body: Center(
              child: AccessibleInteractiveRegion(
                semanticLabel: "Add attachment",
                persistentLabel: "Attach",
                onActivate: () => regionActivations += 1,
                child: InkWell(
                  onTap: () => childActivations += 1,
                  child: const SizedBox(
                    width: 24,
                    height: 24,
                    child: Icon(Icons.add),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.add));

    expect(childActivations, 1);
    expect(regionActivations, 0);
  });

  testWidgets("persistent action label does not stretch to bounded max height",
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Scaffold(
            body: SizedBox(
              height: 200,
              child: Row(
                children: [
                  AccessibleInteractiveRegion(
                    semanticLabel: "Add attachment",
                    persistentLabel: "Attach",
                    minimumSize: 44,
                    onActivate: () {},
                    child: const SizedBox(width: 44, height: 44),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(AccessibleInteractiveRegion));

    expect(size.height, lessThan(64));
  });
}
