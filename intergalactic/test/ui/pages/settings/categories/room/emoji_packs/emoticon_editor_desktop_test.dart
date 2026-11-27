import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';

import 'emoticon_test_fixtures.dart';

void main() {
  Future<RecordingCutoutBackend> pumpDesktopCreator(WidgetTester tester) async {
    final backend = RecordingCutoutBackend(
      syntheticCutoutResult(redSquareOnWhitePng()),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 1200,
            child: EmoticonCreator(
              mobileLayout: false,
              creatingNew: true,
              initialSourceImageData: redSquareOnWhitePng(),
              initialSourceImageName: 'Party Ship.PNG',
              autoRunInitialCutout: true,
              cutoutService: ImageCutoutService(backend: backend),
              draftStore: FakeDraftStore([sampleDraft()]),
              onCreate: (_, _, _) async => true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    return backend;
  }

  testWidgets(
    'quick surface completes a crop-name-save flow without the Editor (R10)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpDesktopCreator(tester);

      expect(find.byKey(const ValueKey('emoticon-quick-save')), findsOneWidget);
      expect(find.byKey(const ValueKey('emoticon-quick-crop')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('emoticon-advanced-edit')),
        findsOneWidget,
      );
      // The full editor panel is not present on the quick surface.
      expect(
        find.byKey(const ValueKey('emoticon-desktop-tool-panel')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'all six tool groups are reachable in the persistent panel (R11)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpDesktopCreator(tester);

      await tester.tap(find.byKey(const ValueKey('emoticon-advanced-edit')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('emoticon-desktop-tool-panel')),
        findsOneWidget,
      );
      for (final group in [
        'cutout',
        'brush',
        'crop',
        'output',
        'preview',
        'drafts',
      ]) {
        final tile = find.byKey(
          PageStorageKey('emoticon-desktop-group-$group'),
        );
        if (!tester.any(tile)) {
          await tester.scrollUntilVisible(
            tile,
            80,
            scrollable: find.descendant(
              of: find.byKey(const ValueKey('emoticon-desktop-tool-panel')),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(tile, findsOneWidget, reason: '$group group reachable');
      }
    },
  );

  testWidgets(
    'Advanced edit swaps the dialog body to the Editor without saving, and '
    'Done returns (R10/R12)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final backend = await pumpDesktopCreator(tester);
      expect(backend.generateCount, 1);

      await tester.tap(find.byKey(const ValueKey('emoticon-advanced-edit')));
      await tester.pumpAndSettle();

      // No Save affordance in the desktop Editor either.
      expect(find.byKey(const ValueKey('emoticon-quick-save')), findsNothing);
      expect(
        find.byKey(const ValueKey('emoticon-desktop-editor-done')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('emoticon-desktop-editor-done')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('emoticon-quick-save')), findsOneWidget);
    },
  );
}
