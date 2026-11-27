import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';

import 'emoticon_test_fixtures.dart';

void main() {
  testWidgets(
    'mobile: Done returns the shaped image to the Quick card and only the '
    'card saves (R6)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final createdShortcodes = <String>[];
      Uint8List? createdBytes;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmoticonCreator(
              mobileLayout: true,
              creatingNew: true,
              initialSourceImageData: redSquareOnWhitePng(),
              initialSourceImageName: 'Party Ship.PNG',
              cutoutService: ImageCutoutService(
                backend: RecordingCutoutBackend(
                  syntheticCutoutResult(redSquareOnWhitePng()),
                ),
              ),
              draftStore: FakeDraftStore(),
              onCreate: (shortcode, usage, data) async {
                createdShortcodes.add(shortcode);
                createdBytes = data;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.byKey(const ValueKey('emoticon-advanced-edit')));
      await tester.pumpAndSettle();

      // Run the cutout inside the Editor, then commit with Done.
      await tester.tap(find.byKey(const ValueKey('emoticon-tool-tab-cutout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('emoticon-auto-cutout')));
      await tester.pumpAndSettle();

      expect(createdShortcodes, isEmpty, reason: 'Editor never saves');

      await tester.tap(find.byKey(const ValueKey('emoticon-editor-done')));
      await tester.pumpAndSettle();

      // Back on the Quick card, save persists name + usage + shaped image.
      expect(find.byKey(const ValueKey('emoticon-quick-save')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('emoticon-quick-save')));
      await tester.pumpAndSettle();

      expect(createdShortcodes, ['party_ship']);
      expect(createdBytes, isNotNull);
    },
  );

  testWidgets('mobile: cutout can be saved to Photos without closing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? savedFilename;
    Uint8List? savedBytes;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmoticonCreator(
            mobileLayout: true,
            creatingNew: true,
            initialSourceImageData: redSquareOnWhitePng(),
            initialSourceImageName: 'Party Ship.PNG',
            autoRunInitialCutout: true,
            cutoutService: ImageCutoutService(
              backend: RecordingCutoutBackend(
                syntheticCutoutResult(redSquareOnWhitePng()),
              ),
            ),
            draftStore: FakeDraftStore(),
            onCreate: (_, _, _) async => true,
            onSaveToPhotos: (filename, bytes) async {
              savedFilename = filename;
              savedBytes = bytes;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('emoticon-save-to-photos')));
    await tester.pumpAndSettle();

    expect(savedFilename, 'party_ship.png');
    expect(savedBytes, isNotNull);
    expect(find.text('Saved cutout to Photos.'), findsOneWidget);
    expect(find.byKey(const ValueKey('emoticon-quick-save')), findsOneWidget);
  });

  testWidgets('mobile: Back discards the Editor session (R2)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final backend = RecordingCutoutBackend(
      syntheticCutoutResult(redSquareOnWhitePng()),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmoticonCreator(
            mobileLayout: true,
            creatingNew: true,
            initialSourceImageData: redSquareOnWhitePng(),
            initialSourceImageName: 'Party Ship.PNG',
            cutoutService: ImageCutoutService(backend: backend),
            draftStore: FakeDraftStore(),
            onCreate: (_, _, _) async => true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const ValueKey('emoticon-advanced-edit')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('emoticon-tool-tab-cutout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('emoticon-auto-cutout')));
    await tester.pumpAndSettle();
    expect(backend.generateCount, 1);

    await tester.tap(find.byKey(const ValueKey('emoticon-editor-back')));
    await tester.pumpAndSettle();

    // Re-entering the Editor shows the pre-session state: the cutout was
    // discarded, so the auto-cutout status is gone.
    expect(find.textContaining('Transparent PNG ready.'), findsNothing);
    expect(find.byKey(const ValueKey('emoticon-quick-save')), findsOneWidget);
  });

  testWidgets('mobile: invalid shortcode surfaces error and disables save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final created = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmoticonCreator(
            mobileLayout: true,
            creatingNew: true,
            initialSourceImageData: redSquareOnWhitePng(),
            cutoutService: ImageCutoutService(
              backend: RecordingCutoutBackend(
                syntheticCutoutResult(redSquareOnWhitePng()),
              ),
            ),
            draftStore: FakeDraftStore(),
            onCreate: (shortcode, _, _) async {
              created.add(shortcode);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.enterText(find.byType(EditableText).first, 'Bad Name!');
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('emoticon-quick-save')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(created, isEmpty);
  });

  testWidgets('mobile: usage selection round-trips to the save callback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    EmoticonUsage? savedUsage;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmoticonCreator(
            mobileLayout: true,
            creatingNew: true,
            initialSourceImageData: redSquareOnWhitePng(),
            initialSourceImageName: 'Party Ship.PNG',
            cutoutService: ImageCutoutService(
              backend: RecordingCutoutBackend(
                syntheticCutoutResult(redSquareOnWhitePng()),
              ),
            ),
            draftStore: FakeDraftStore(),
            onCreate: (_, usage, _) async {
              savedUsage = usage;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Follow Pack'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emoji').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('emoticon-quick-save')));
    await tester.pumpAndSettle();

    expect(savedUsage, EmoticonUsage.emoji);
  });
}
