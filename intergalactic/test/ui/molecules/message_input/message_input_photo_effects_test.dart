import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/molecules/message_input.dart';

void main() {
  testWidgets('effects menu omits photo actions without photos', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ComposerEffectsMenuContent(onSelected: _ignoreEffect),
        ),
      ),
    );

    expect(find.text('Attached photos'), findsNothing);
    expect(find.text('Hide photos'), findsNothing);
    expect(find.text('Show photos'), findsNothing);
  });

  testWidgets('effects menu exposes photo hiding when photos are attached', (
    tester,
  ) async {
    var toggles = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposerEffectsMenuContent(
            onSelected: (_) {},
            hasPhotoAttachments: true,
            photoAttachmentsHidden: false,
            onTogglePhotoVisibility: () => toggles++,
          ),
        ),
      ),
    );

    expect(find.text('Attached photos'), findsOneWidget);
    await tester.tap(find.text('Hide photos'));

    expect(toggles, 1);
  });

  testWidgets('effects menu omits a photo action without a callback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ComposerEffectsMenuContent(
            onSelected: _ignoreEffect,
            hasPhotoAttachments: true,
          ),
        ),
      ),
    );

    expect(find.text('Attached photos'), findsNothing);
    expect(find.text('Hide photos'), findsNothing);
  });

  testWidgets('effects menu shows the reveal action for hidden photos', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ComposerEffectsMenuContent(
            onSelected: _ignoreEffect,
            hasPhotoAttachments: true,
            photoAttachmentsHidden: true,
            onTogglePhotoVisibility: _ignoreToggle,
          ),
        ),
      ),
    );

    expect(find.text('Show photos'), findsOneWidget);
    expect(find.text('Hide photos'), findsNothing);
  });
}

void _ignoreEffect(ComposerEffectOption _) {}

void _ignoreToggle() {}
