import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';

void main() {
  testWidgets('anchor registry remeasures after viewport size changes', (
    tester,
  ) async {
    final registry = TutorialAnchorRegistry();
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      _AnchorViewportHost(registry: registry, viewport: const Size(400, 300)),
    );
    await tester.pump();
    await tester.pump();

    expect(registry.rectFor('target')?.width, 100);

    await tester.pumpWidget(
      _AnchorViewportHost(registry: registry, viewport: const Size(800, 300)),
    );
    await tester.pump();
    await tester.pump();

    expect(registry.rectFor('target')?.width, 200);
  });

  testWidgets('anchor remeasures after animated child size changes', (
    tester,
  ) async {
    final registry = TutorialAnchorRegistry();
    addTearDown(registry.dispose);
    var expanded = false;

    Widget buildHost() {
      return MaterialApp(
        home: TutorialAnchorScope(
          registry: registry,
          child: Center(
            child: TutorialAnchor(
              id: TutorialAnchorIds.composerPopup,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                child: SizedBox(
                  key: ValueKey(expanded),
                  width: expanded ? 320 : 140,
                  height: expanded ? 240 : 120,
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    expect(registry.rectFor(TutorialAnchorIds.composerPopup)?.width, 140);

    expanded = true;
    await tester.pumpWidget(buildHost());
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    expect(registry.rectFor(TutorialAnchorIds.composerPopup)?.width, 320);
  });

  testWidgets(
    'anchors measure inside the tutorial canvas after chrome offset',
    (tester) async {
      final registry = TutorialAnchorRegistry();
      addTearDown(registry.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: Column(
              children: [
                const SizedBox(height: 40),
                Expanded(
                  child: TutorialAnchorScope(
                    registry: registry,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: TutorialAnchor(
                        id: 'chrome-offset-target',
                        child: const SizedBox(width: 120, height: 44),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final rect = registry.rectFor('chrome-offset-target');
      expect(rect?.top, 0);
      expect(rect?.left, 0);
      expect(rect?.width, 120);
      expect(rect?.height, 44);
    },
  );
}

class _AnchorViewportHost extends StatelessWidget {
  const _AnchorViewportHost({required this.registry, required this.viewport});

  final TutorialAnchorRegistry registry;
  final Size viewport;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SizedBox.fromSize(
        size: viewport,
        child: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              registry.updateViewport(viewport);
            });

            return TutorialAnchorScope(
              registry: registry,
              child: Align(
                alignment: Alignment.topLeft,
                child: TutorialAnchor(
                  id: 'target',
                  child: SizedBox(width: viewport.width / 4, height: 48),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
