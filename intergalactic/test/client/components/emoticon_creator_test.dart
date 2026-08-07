import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:intergalactic/client/components/emoticon/emoticon_creator_validation.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';
import 'package:intergalactic/utils/picker_utils.dart';

void main() {
  group('ImageCutoutService', () {
    test(
      'generates a transparent PNG from a border-connected background',
      () async {
        final service = ImageCutoutService();
        final result = await service.generate(
          imageBytes: _redSquareOnWhitePng(),
          settings: const CutoutSettings(
            edgeSoftness: 1,
            paddingFraction: 0.08,
            maxProcessingDimension: 64,
            maxOutputDimension: 64,
          ),
        );

        expect(result.backend, ImageCutoutBackendType.localEdgeSegmentation);
        expect(transparentPngHasAlpha(result.pngBytes), isTrue);

        final decoded = img.decodePng(result.pngBytes)!;
        final corner = decoded.getPixel(0, 0);
        final center = decoded.getPixel(
          decoded.width ~/ 2,
          decoded.height ~/ 2,
        );
        expect(corner.a, lessThan(40));
        expect(center.a, greaterThan(180));
        expect(center.r, greaterThan(center.g));
      },
    );

    test('outline keeps transparent pixels available', () async {
      final service = ImageCutoutService();
      final result = await service.generate(
        imageBytes: _redSquareOnWhitePng(),
        settings: const CutoutSettings(
          edgeSoftness: 1,
          outlineWidth: 3,
          maxProcessingDimension: 64,
          maxOutputDimension: 64,
        ),
      );

      final decoded = img.decodePng(result.pngBytes)!;
      final alphaValues = decoded.map((pixel) => pixel.a.round()).toList();
      expect(alphaValues.any((alpha) => alpha == 0), isTrue);
      expect(alphaValues.any((alpha) => alpha > 200), isTrue);
    });

    test('manual erase brush lowers mask alpha', () async {
      final service = ImageCutoutService();
      final result = await service.generate(
        imageBytes: _redSquareOnWhitePng(),
        settings: const CutoutSettings(
          edgeSoftness: 0,
          maxProcessingDimension: 64,
          maxOutputDimension: 64,
        ),
      );

      final centerIndex =
          (result.mask.height ~/ 2) * result.mask.width +
          result.mask.width ~/ 2;
      final before = result.mask.alpha[centerIndex];
      final erased = result.mask.applyBrush(
        normalizedX: 0.5,
        normalizedY: 0.5,
        radiusFraction: 0.1,
        mode: CutoutBrushMode.erase,
      );

      expect(erased.alpha[centerIndex], lessThan(before));
    });

    test('malformed image bytes return image decode failure', () async {
      final service = ImageCutoutService();

      await expectLater(
        service.generate(imageBytes: Uint8List.fromList(const [1, 2, 3, 4])),
        throwsA(
          isA<ImageCutoutException>().having(
            (error) => error.code,
            'code',
            ImageCutoutFailureCode.imageDecodeFailed,
          ),
        ),
      );
    });

    test('flat image without a subject returns no-subject failure', () async {
      final service = ImageCutoutService();

      await expectLater(
        service.generate(
          imageBytes: _solidWhitePng(),
          settings: const CutoutSettings(
            edgeSoftness: 0,
            maxProcessingDimension: 64,
            maxOutputDimension: 64,
          ),
        ),
        throwsA(
          isA<ImageCutoutException>().having(
            (error) => error.code,
            'code',
            ImageCutoutFailureCode.noSubjectFound,
          ),
        ),
      );
    });

    test('large images are bounded for mask generation and output', () async {
      final service = ImageCutoutService();
      final result = await service.generate(
        imageBytes: _largeRedSquareOnWhitePng(),
        settings: const CutoutSettings(
          edgeSoftness: 0,
          paddingFraction: 0.08,
          maxProcessingDimension: 40,
          maxOutputDimension: 48,
        ),
      );

      expect(
        math.max(result.mask.width, result.mask.height),
        lessThanOrEqualTo(40),
      );
      expect(math.max(result.width, result.height), lessThanOrEqualTo(48));
      expect(result.sourceWidth, 400);
      expect(result.sourceHeight, 320);
    });

    test('exported PNG omits metadata chunks', () async {
      final service = ImageCutoutService();
      final result = await service.generate(
        imageBytes: _redSquareOnWhitePng(),
        settings: const CutoutSettings(
          edgeSoftness: 1,
          maxProcessingDimension: 64,
          maxOutputDimension: 64,
        ),
      );

      final metadataChunks = _pngChunkTypes(
        result.pngBytes,
      ).where(const {'tEXt', 'iTXt', 'zTXt', 'eXIf'}.contains);

      expect(metadataChunks, isEmpty);
    });

    test('unsupported backend returns a structured failure', () async {
      final service = ImageCutoutService(
        backend: const UnsupportedImageCutoutBackend(),
      );

      expect(
        () => service.generate(imageBytes: _redSquareOnWhitePng()),
        throwsA(
          isA<ImageCutoutException>().having(
            (error) => error.code,
            'code',
            ImageCutoutFailureCode.unsupportedPlatform,
          ),
        ),
      );
    });

    test('selects local fallback while preserving native preference', () {
      final appleSelection = ImageCutoutBackendSelector.selectForHost(
        hostPlatform: ImageCutoutHostPlatform.apple,
      );
      final androidSelection = ImageCutoutBackendSelector.selectForHost(
        hostPlatform: ImageCutoutHostPlatform.android,
      );
      final desktopSelection = ImageCutoutBackendSelector.selectForHost(
        hostPlatform: ImageCutoutHostPlatform.desktop,
      );

      expect(
        appleSelection.preferredType,
        ImageCutoutBackendType.appleVisionSubjectLift,
      );
      expect(
        androidSelection.preferredType,
        ImageCutoutBackendType.androidMlKitSubjectSegmentation,
      );
      expect(
        desktopSelection.preferredType,
        ImageCutoutBackendType.onnxBackgroundRemoval,
      );
      expect([
        appleSelection.selectedType,
        androidSelection.selectedType,
        desktopSelection.selectedType,
      ], everyElement(ImageCutoutBackendType.localEdgeSegmentation));
      expect(appleSelection.usesFallback, isTrue);
      expect(androidSelection.usesFallback, isTrue);
      expect(desktopSelection.usesFallback, isTrue);
    });

    test('reports native and model backends as unavailable explicitly', () {
      final apple = ImageCutoutBackendSelector.describe(
        ImageCutoutBackendType.appleVisionSubjectLift,
      );
      final android = ImageCutoutBackendSelector.describe(
        ImageCutoutBackendType.androidMlKitSubjectSegmentation,
      );
      final desktop = ImageCutoutBackendSelector.describe(
        ImageCutoutBackendType.onnxBackgroundRemoval,
      );

      expect(apple.isAvailable, isFalse);
      expect(apple.failureCode, ImageCutoutFailureCode.unsupportedPlatform);
      expect(apple.requiresNativeBridge, isTrue);
      expect(android.isAvailable, isFalse);
      expect(android.failureCode, ImageCutoutFailureCode.modelNotAvailable);
      expect(android.requiresNativeBridge, isTrue);
      expect(android.requiresModelArtifact, isTrue);
      expect(desktop.isAvailable, isFalse);
      expect(desktop.failureCode, ImageCutoutFailureCode.modelNotAvailable);
      expect(desktop.requiresModelArtifact, isTrue);
    });

    test(
      'can disable local fallback for a structured desktop failure',
      () async {
        final service = ImageCutoutService(
          hostPlatform: ImageCutoutHostPlatform.desktop,
          allowLocalFallback: false,
        );

        expect(
          service.selection.preferredType,
          ImageCutoutBackendType.onnxBackgroundRemoval,
        );
        expect(
          service.selection.selectedType,
          ImageCutoutBackendType.onnxBackgroundRemoval,
        );
        await expectLater(
          service.generate(imageBytes: _redSquareOnWhitePng()),
          throwsA(
            isA<ImageCutoutException>().having(
              (error) => error.code,
              'code',
              ImageCutoutFailureCode.modelNotAvailable,
            ),
          ),
        );
      },
    );
  });

  group('validateEmoticonShortcode', () {
    test('accepts lowercase shortcode', () {
      final result = validateEmoticonShortcode('party_ship');

      expect(result.isValid, isTrue);
      expect(result.normalized, 'party_ship');
    });

    test('rejects duplicate shortcode', () {
      final result = validateEmoticonShortcode(
        'party',
        existingShortcodes: const ['party'],
      );

      expect(result.code, EmoticonShortcodeValidationCode.duplicate);
    });

    test('rejects uppercase shortcode before normalizing', () {
      final result = validateEmoticonShortcode('Party');

      expect(result.code, EmoticonShortcodeValidationCode.uppercase);
      expect(result.normalized, 'party');
    });
  });

  group('EmoticonCreator draft panel', () {
    testWidgets('loads and deletes recent local drafts', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bytes = _redSquareOnWhitePng();
      final draft = EmoticonDraft(
        id: 'draft-1',
        shortcode: 'party',
        outputPngPath: 'draft-1.png',
        thumbnailPath: 'draft-1-thumb.png',
        backend: ImageCutoutBackendType.localEdgeSegmentation,
        createdAt: DateTime.utc(2026, 7, 5, 12),
        width: 64,
        height: 64,
        fileSize: bytes.length,
      );
      final store = _FakeDraftStore(
        draft: draft,
        pngBytes: bytes,
        thumbnailBytes: bytes,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              height: 1200,
              child: EmoticonCreator(
                draftStore: store,
                onCreate: (_, _, _) async => true,
              ),
            ),
          ),
        ),
      );
      await _pumpCreator(tester);

      expect(find.text('Recent drafts'), findsOneWidget);
      expect(find.text('party'), findsOneWidget);

      await _tapVisible(tester, find.widgetWithText(TextButton, 'Load'));

      expect(find.text('Loaded'), findsOneWidget);
      expect(
        find.text('Loaded local draft. Save to add it to this pack.'),
        findsOneWidget,
      );

      await _tapVisible(tester, find.byIcon(Icons.delete_outline_rounded));
      await _tapVisible(tester, find.text('Delete').last);

      expect(store.deletedIds, const ['draft-1']);
      expect(find.text('Recent drafts'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Load'), findsNothing);
    });

    testWidgets('filters local drafts and clears an empty search', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bytes = _redSquareOnWhitePng();
      final store = _DraftRecordStore([
        _draftData(
          id: 'draft-party',
          shortcode: 'party_ship',
          bytes: bytes,
          createdAt: DateTime.utc(2026, 7, 5, 14),
        ),
        _draftData(
          id: 'draft-cat',
          shortcode: 'nebula_cat',
          bytes: bytes,
          createdAt: DateTime.utc(2026, 7, 5, 13),
          width: 128,
          height: 128,
        ),
        _draftData(
          id: 'draft-moon',
          shortcode: 'tiny_moon',
          bytes: bytes,
          createdAt: DateTime.utc(2026, 7, 5, 12),
          width: 32,
          height: 32,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              height: 1200,
              child: EmoticonCreator(
                draftStore: store,
                onCreate: (_, _, _) async => true,
              ),
            ),
          ),
        ),
      );
      await _pumpCreator(tester);

      expect(find.text('party_ship'), findsOneWidget);
      expect(find.text('nebula_cat'), findsOneWidget);
      expect(find.text('tiny_moon'), findsOneWidget);

      final search = find.byKey(const ValueKey('emoticon-draft-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'cat');
      await _pumpCreator(tester);

      expect(find.text('nebula_cat'), findsOneWidget);
      expect(find.text('party_ship'), findsNothing);
      expect(find.text('tiny_moon'), findsNothing);

      await tester.enterText(search, 'missing');
      await _pumpCreator(tester);

      expect(find.text('No local drafts found.'), findsOneWidget);
      expect(find.text('Clear search'), findsOneWidget);

      await _tapVisible(tester, find.text('Clear search'));

      expect(find.text('party_ship'), findsOneWidget);
      expect(find.text('nebula_cat'), findsOneWidget);
      expect(find.text('tiny_moon'), findsOneWidget);
    });

    testWidgets('bulk deletes matching local drafts only', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bytes = _redSquareOnWhitePng();
      final store = _DraftRecordStore([
        _draftData(
          id: 'draft-party',
          shortcode: 'party_ship',
          bytes: bytes,
          createdAt: DateTime.utc(2026, 7, 5, 14),
        ),
        _draftData(
          id: 'draft-cat',
          shortcode: 'nebula_cat',
          bytes: bytes,
          createdAt: DateTime.utc(2026, 7, 5, 13),
        ),
        _draftData(
          id: 'draft-moon',
          shortcode: 'tiny_moon',
          bytes: bytes,
          createdAt: DateTime.utc(2026, 7, 5, 12),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              height: 1200,
              child: EmoticonCreator(
                draftStore: store,
                onCreate: (_, _, _) async => true,
              ),
            ),
          ),
        ),
      );
      await _pumpCreator(tester);

      final search = find.byKey(const ValueKey('emoticon-draft-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'cat');
      await _pumpCreator(tester);

      expect(find.text('nebula_cat'), findsOneWidget);
      expect(find.text('party_ship'), findsNothing);
      expect(find.text('tiny_moon'), findsNothing);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('emoticon-draft-bulk-delete')),
      );

      expect(find.text('Delete matching local draft?'), findsOneWidget);
      expect(
        find.textContaining('does not remove Matrix image packs'),
        findsOneWidget,
      );

      await _tapVisible(tester, find.text('Delete').last);

      expect(store.deletedIds, const ['draft-cat']);
      expect(find.text('nebula_cat'), findsNothing);
      expect(find.text('No local drafts found.'), findsOneWidget);

      await _tapVisible(tester, find.text('Clear search'));

      expect(find.text('party_ship'), findsOneWidget);
      expect(find.text('tiny_moon'), findsOneWidget);
      expect(find.text('nebula_cat'), findsNothing);
    });

    testWidgets('keeps save disabled until a local PNG draft is loaded', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bytes = _redSquareOnWhitePng();
      final draft = EmoticonDraft(
        id: 'draft-1',
        shortcode: 'party',
        outputPngPath: 'draft-1.png',
        thumbnailPath: 'draft-1-thumb.png',
        backend: ImageCutoutBackendType.localEdgeSegmentation,
        createdAt: DateTime.utc(2026, 7, 5, 12),
        width: 64,
        height: 64,
        fileSize: bytes.length,
      );
      final store = _FakeDraftStore(
        draft: draft,
        pngBytes: bytes,
        thumbnailBytes: bytes,
      );
      final createdShortcodes = <String>[];
      Uint8List? createdBytes;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              height: 1200,
              child: EmoticonCreator(
                draftStore: store,
                onCreate: (shortcode, usage, data) async {
                  createdShortcodes.add(shortcode);
                  createdBytes = data;
                  return false;
                },
              ),
            ),
          ),
        ),
      );
      await _pumpCreator(tester);

      await _tapVisible(tester, find.text('Save!'), warnIfMissed: false);

      expect(createdShortcodes, isEmpty);

      await _tapVisible(tester, find.widgetWithText(TextButton, 'Load'));
      await _tapVisible(tester, find.text('Save!'));

      expect(createdShortcodes, const ['party']);
      expect(createdBytes, bytes);
    });

    testWidgets(
      'saves generated PNG draft before invoking pack save callback',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final sourceBytes = _redSquareOnWhitePng();
        final cutoutBytes = _blueCircleTransparentPng();
        final cutoutResult = _syntheticCutoutResult(cutoutBytes);
        final backend = _RecordingCutoutBackend(cutoutResult);
        final store = _SavingDraftStore();
        final order = <String>[];
        final createdShortcodes = <String>[];
        Uint8List? createdBytes;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: sourceBytes,
                  initialSourceImageName: 'Saved Party.PNG',
                  autoRunInitialCutout: true,
                  pack: const _FakeEmoticonPack(identifier: 'personal-pack'),
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: store,
                  onCreate: (shortcode, usage, data) async {
                    order.add('pack');
                    createdShortcodes.add(shortcode);
                    createdBytes = data;
                    return false;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await _pumpCreator(tester);

        expect(backend.generateCount, 1);
        expect(find.textContaining('Transparent PNG ready.'), findsOneWidget);

        store.onSave = () => order.add('draft');
        await _tapVisible(tester, find.text('Save!'), warnIfMissed: false);

        expect(order, const ['draft', 'pack']);
        expect(createdShortcodes, const ['saved_party']);
        expect(createdBytes, cutoutBytes);
        expect(store.savedDrafts, hasLength(1));
        expect(store.savedDrafts.single.shortcode, 'saved_party');
        expect(store.savedDrafts.single.pngBytes, cutoutBytes);
        expect(store.savedDrafts.single.thumbnailBytes, cutoutBytes);
        expect(
          store.savedDrafts.single.backend,
          ImageCutoutBackendType.localEdgeSegmentation,
        );
        expect(store.savedDrafts.single.width, cutoutResult.width);
        expect(store.savedDrafts.single.height, cutoutResult.height);
        expect(store.savedDrafts.single.packId, 'personal-pack');
        expect(
          store.savedDrafts.single.sourceImageHash,
          sha256.convert(sourceBytes).toString(),
        );
        expect(
          find.text('Local draft saved. Pack update was not completed.'),
          findsOneWidget,
        );
        expect(find.widgetWithText(TextButton, 'Load'), findsOneWidget);
        expect(find.text('Saving local draft...'), findsNothing);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'refreshes generated drafts when pack save throws',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final sourceBytes = _redSquareOnWhitePng();
        final cutoutBytes = _blueCircleTransparentPng();
        final backend = _RecordingCutoutBackend(
          _syntheticCutoutResult(cutoutBytes),
        );
        final store = _SavingDraftStore();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: sourceBytes,
                  initialSourceImageName: 'Saved Party.PNG',
                  autoRunInitialCutout: true,
                  pack: const _FakeEmoticonPack(identifier: 'personal-pack'),
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: store,
                  onCreate: (_, _, _) async => throw StateError('pack failed'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await _pumpCreator(tester);

        await _tapVisible(tester, find.text('Save!'), warnIfMissed: false);

        expect(store.savedDrafts, hasLength(1));
        expect(find.text('This emoticon could not be saved.'), findsOneWidget);
        expect(
          find.text('Local draft saved. Pack update was not completed.'),
          findsOneWidget,
        );
        expect(find.widgetWithText(TextButton, 'Load'), findsOneWidget);
        expect(find.text('Saving local draft...'), findsNothing);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'exposes editor accessibility labels and disabled manual controls',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        try {
          final bytes = _redSquareOnWhitePng();
          final draft = EmoticonDraft(
            id: 'draft-1',
            shortcode: 'party',
            outputPngPath: 'draft-1.png',
            thumbnailPath: 'draft-1-thumb.png',
            backend: ImageCutoutBackendType.localEdgeSegmentation,
            createdAt: DateTime.utc(2026, 7, 5, 12),
            width: 64,
            height: 64,
            fileSize: bytes.length,
          );
          final store = _FakeDraftStore(
            draft: draft,
            pngBytes: bytes,
            thumbnailBytes: bytes,
          );

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 700,
                  height: 1200,
                  child: EmoticonCreator(draftStore: store),
                ),
              ),
            ),
          );
          await _pumpCreator(tester);

          expect(
            find.bySemanticsLabel(
              'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
            ),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel('Preview background mode'),
            findsOneWidget,
          );
          expect(find.text('Checkerboard'), findsOneWidget);
          expect(find.text('Dark'), findsOneWidget);
          expect(find.text('Light'), findsOneWidget);
          expect(find.text('Crop'), findsOneWidget);
          expect(find.text('Square crop'), findsOneWidget);
          expect(find.text('Tight crop'), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == 'Local emoticon drafts',
            ),
            findsOneWidget,
          );

          final eraseChip = tester.widget<FilterChip>(
            find.widgetWithText(FilterChip, 'Erase'),
          );
          final restoreChip = tester.widget<FilterChip>(
            find.widgetWithText(FilterChip, 'Restore'),
          );
          final squareCropChip = tester.widget<FilterChip>(
            find.widgetWithText(FilterChip, 'Square crop'),
          );
          final tightCropChip = tester.widget<FilterChip>(
            find.widgetWithText(FilterChip, 'Tight crop'),
          );
          final shadowSwitch = tester.widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Shadow'),
          );

          expect(eraseChip.onSelected, isNull);
          expect(restoreChip.onSelected, isNull);
          expect(squareCropChip.onSelected, isNull);
          expect(tightCropChip.onSelected, isNull);
          expect(shadowSwitch.onChanged, isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  });

  group('EmoticonCreator cutout states', () {
    testWidgets(
      'picker read failure shows a clear error without starting cutout',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        var pickerCallCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  pickSourceImage: () async {
                    pickerCallCount++;
                    return const _ThrowingPickerResult('Broken Photo.PNG');
                  },
                  cutoutService: ImageCutoutService(
                    backend: _RecordingCutoutBackend(
                      _syntheticCutoutResult(_redSquareOnWhitePng()),
                    ),
                  ),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: _redSquareOnWhitePng(),
                    thumbnailBytes: _redSquareOnWhitePng(),
                  ),
                ),
              ),
            ),
          ),
        );
        await _pumpCreator(tester);

        await _tapVisible(
          tester,
          find.text('Select photo').last,
          warnIfMissed: false,
        );

        expect(pickerCallCount, 1);
        expect(find.text('This photo could not be loaded.'), findsOneWidget);
        expect(find.text('broken_photo'), findsNothing);
        expect(find.textContaining('Transparent PNG ready.'), findsNothing);
        expect(
          find.text('Preparing local background removal...'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'auto cutout failure clears processing status and keeps source editable',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bytes = _redSquareOnWhitePng();
        final backend = _ThrowingCutoutBackend(
          generateException: const ImageCutoutException(
            ImageCutoutFailureCode.noSubjectFound,
            'No foreground subject was found.',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  pickSourceImage: () async =>
                      _FakePickerResult(bytes, name: 'Flat Robot.PNG'),
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: bytes,
                    thumbnailBytes: bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await _pumpCreator(tester);

        await _tapVisible(
          tester,
          find.text('Select photo').last,
          warnIfMissed: false,
        );

        expect(find.text('flat_robot'), findsOneWidget);

        await _tapVisible(tester, find.text('Auto'));

        expect(backend.generateCount, 1);
        expect(find.text('No foreground subject was found.'), findsOneWidget);
        expect(
          find.text('Preparing local background removal...'),
          findsNothing,
        );
        expect(find.textContaining('Transparent PNG ready.'), findsNothing);
        expect(find.text('Change photo'), findsOneWidget);

        final eraseChip = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, 'Erase'),
        );
        expect(eraseChip.onSelected, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'render failure clears updating status and preserves the current cutout',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bytes = _redSquareOnWhitePng();
        final autoResult = _syntheticCutoutResult(bytes);
        final backend = _ThrowingCutoutBackend(
          generateResult: autoResult,
          renderException: const ImageCutoutException(
            ImageCutoutFailureCode.processingFailed,
            'Render failed.',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: bytes,
                  initialSourceImageName: 'Party Ship.PNG',
                  autoRunInitialCutout: true,
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: bytes,
                    thumbnailBytes: bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await _pumpCreator(tester);

        expect(backend.generateCount, 1);
        expect(find.textContaining('Transparent PNG ready.'), findsOneWidget);

        final previewGesture = find.descendant(
          of: find.bySemanticsLabel(
            'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
          ),
          matching: find.byType(GestureDetector),
        );
        await tester.tap(previewGesture);
        await tester.pump(const Duration(milliseconds: 180));
        await _pumpCreator(tester);

        expect(backend.renderCount, 1);
        expect(find.text('This edit could not be applied.'), findsOneWidget);
        expect(find.text('Updating transparent PNG...'), findsNothing);
        expect(find.textContaining('Transparent PNG ready.'), findsNothing);
        expect(find.text('Backend: localEdgeSegmentation'), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'renders processing and preview states for a preloaded source',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bytes = _redSquareOnWhitePng();
        final result = _syntheticCutoutResult(bytes);
        final backend = _DeferredCutoutBackend();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: bytes,
                  initialSourceImageName: 'Party Ship.PNG',
                  autoRunInitialCutout: true,
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: bytes,
                    thumbnailBytes: bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Processing...'), findsOneWidget);
        expect(
          find.text('Preparing local background removal...'),
          findsOneWidget,
        );
        expect(find.text('party_ship'), findsOneWidget);

        backend.complete(result);
        await _pumpCreator(tester);

        expect(find.textContaining('Transparent PNG ready.'), findsOneWidget);
        expect(find.text('Backend: localEdgeSegmentation'), findsOneWidget);
        expect(find.text('Metadata stripped on export'), findsOneWidget);
        expect(find.text('Sensitivity'), findsOneWidget);
        expect(find.text('Softness'), findsOneWidget);
        expect(find.text('Edge offset'), findsOneWidget);
        expect(find.text('Checkerboard'), findsOneWidget);
        expect(find.text('Dark'), findsOneWidget);
        expect(find.text('Light'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Crop framing',
          ),
          findsOneWidget,
        );
        expect(find.text('Crop'), findsOneWidget);
        expect(find.text('Square crop'), findsOneWidget);
        expect(find.text('Tight crop'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Emoji-size preview on checkerboard background',
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            'Sticker-size preview on checkerboard background',
          ),
          findsOneWidget,
        );
        expect(find.byType(Image), findsWidgets);

        await tester.tap(find.widgetWithText(FilterChip, 'Dark'));
        await _pumpCreator(tester);
        expect(
          find.bySemanticsLabel(
            'Transparent cutout preview on dark background. Drag on the image to refine the mask.',
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Emoji-size preview on dark background'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(FilterChip, 'Light'));
        await _pumpCreator(tester);
        expect(
          find.bySemanticsLabel(
            'Transparent cutout preview on light background. Drag on the image to refine the mask.',
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Sticker-size preview on light background'),
          findsOneWidget,
        );

        final eraseChip = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, 'Erase'),
        );
        final restoreChip = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, 'Restore'),
        );
        final squareCropChip = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, 'Square crop'),
        );
        final tightCropChip = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, 'Tight crop'),
        );
        final shadowSwitch = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Shadow'),
        );

        expect(eraseChip.onSelected, isNotNull);
        expect(restoreChip.onSelected, isNotNull);
        expect(squareCropChip.selected, isTrue);
        expect(squareCropChip.onSelected, isNotNull);
        expect(tightCropChip.selected, isFalse);
        expect(tightCropChip.onSelected, isNotNull);
        expect(shadowSwitch.onChanged, isNotNull);

        await tester.tap(find.widgetWithText(FilterChip, 'Tight crop'));
        await _pumpCreator(tester);
        final updatedTightCropChip = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, 'Tight crop'),
        );
        expect(updatedTightCropChip.selected, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'surfaces privacy-filtered cutout diagnostics for rebuilt QA',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bytes = _redSquareOnWhitePng();
        final result = _syntheticCutoutResult(bytes);
        final backend = _RecordingCutoutBackend(result);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: bytes,
                  initialSourceImageName: 'Party Ship.PNG',
                  autoRunInitialCutout: true,
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: bytes,
                    thumbnailBytes: bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await _pumpCreator(tester);

        expect(backend.generateCount, 1);
        expect(find.textContaining('Transparent PNG ready.'), findsOneWidget);
        expect(find.text('Cutout details'), findsOneWidget);
        expect(find.text('Operation: generate'), findsOneWidget);
        expect(
          find.text('Runtime backend: localEdgeSegmentation'),
          findsOneWidget,
        );
        expect(find.textContaining('Selected: '), findsOneWidget);
        expect(find.textContaining('Fallback: '), findsOneWidget);
        expect(find.text('Result: success'), findsOneWidget);
        expect(find.text('Source: 64 x 64'), findsOneWidget);
        expect(find.text('Mask: 64 x 64'), findsOneWidget);
        expect(find.textContaining('PNG: '), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'sensitivity rerun regenerates instead of reusing the last auto mask',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bytes = _redSquareOnWhitePng();
        final result = _syntheticCutoutResult(bytes);
        final backend = _RecordingCutoutBackend(result);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: bytes,
                  initialSourceImageName: 'Party Ship.PNG',
                  autoRunInitialCutout: true,
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: bytes,
                    thumbnailBytes: bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await _pumpCreator(tester);

        expect(backend.generateCount, 1);
        expect(backend.renderMasks, isEmpty);

        final sensitivitySlider = find.byWidgetPredicate(
          (widget) => widget is Slider && widget.min == 20 && widget.max == 96,
        );
        await tester.drag(sensitivitySlider, const Offset(140, 0));
        await _pumpCreator(tester);

        expect(backend.generateCount, greaterThan(1));
        expect(backend.renderMasks, isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'auto action recomputes instead of preserving manual brush edits',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bytes = _redSquareOnWhitePng();
        final autoResult = _syntheticCutoutResult(bytes);
        final backend = _RecordingCutoutBackend(autoResult);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: bytes,
                  initialSourceImageName: 'Party Ship.PNG',
                  autoRunInitialCutout: true,
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: bytes,
                    thumbnailBytes: bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await _pumpCreator(tester);

        final previewGesture = find.descendant(
          of: find.bySemanticsLabel(
            'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
          ),
          matching: find.byType(GestureDetector),
        );
        await tester.tap(previewGesture);
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pump();

        expect(backend.generateCount, 1);
        expect(backend.renderMasks, hasLength(1));

        await tester.tap(find.text('Auto'));
        await _pumpCreator(tester);

        expect(backend.generateCount, 2);
        expect(backend.renderMasks, hasLength(1));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'manual edit controls disable while a cutout rerender is pending',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bytes = _redSquareOnWhitePng();
        final autoResult = _syntheticCutoutResult(bytes);
        final backend = _DeferredRenderCutoutBackend(autoResult);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: bytes,
                  initialSourceImageName: 'Party Ship.PNG',
                  autoRunInitialCutout: true,
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: bytes,
                    thumbnailBytes: bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await _pumpCreator(tester);

        var previewGesture = find.descendant(
          of: find.bySemanticsLabel(
            'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
          ),
          matching: find.byType(GestureDetector),
        );
        await tester.tap(previewGesture);
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pump();

        expect(backend.renderMasks, hasLength(1));
        previewGesture = find.descendant(
          of: find.bySemanticsLabel(
            'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
          ),
          matching: find.byType(GestureDetector),
        );
        expect(
          tester.widget<GestureDetector>(previewGesture).onTapDown,
          isNull,
        );
        expect(
          tester
              .widget<FilterChip>(find.widgetWithText(FilterChip, 'Erase'))
              .onSelected,
          isNull,
        );
        expect(
          tester
              .widget<FilterChip>(
                find.widgetWithText(FilterChip, 'Square crop'),
              )
              .onSelected,
          isNull,
        );
        expect(
          tester
              .widget<Slider>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is Slider && widget.min == 0 && widget.max == 10,
                ),
              )
              .onChanged,
          isNull,
        );
        expect(
          tester
              .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Shadow'),
              )
              .onChanged,
          isNull,
        );

        backend.completeRender();
        await _pumpCreator(tester);
        expect(find.text('Transparent PNG updated.'), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'ignores brush strokes in preview letterbox padding',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bytes = _wideSubjectPng();
        final autoResult = _syntheticWideCutoutResult(bytes);
        final backend = _RecordingCutoutBackend(autoResult);
        final centerIndex =
            (autoResult.mask.height ~/ 2) * autoResult.mask.width +
            autoResult.mask.width ~/ 2;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: bytes,
                  initialSourceImageName: 'Wide Ship.PNG',
                  autoRunInitialCutout: true,
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: bytes,
                    thumbnailBytes: bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await _pumpCreator(tester);

        final previewGesture = find.descendant(
          of: find.bySemanticsLabel(
            'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
          ),
          matching: find.byType(GestureDetector),
        );
        final previewRect = tester.getRect(previewGesture);
        await tester.tapAt(
          previewRect.topLeft + Offset(previewRect.width / 2, 24),
        );
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pump();

        expect(backend.renderMasks, isEmpty);

        await tester.tapAt(previewRect.center);
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pump();

        expect(backend.renderMasks, hasLength(1));
        expect(
          backend.renderMasks.single.alpha[centerIndex],
          lessThan(autoResult.mask.alpha[centerIndex]),
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'reset restores the last auto mask after manual edits',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bytes = _redSquareOnWhitePng();
        final autoResult = _syntheticCutoutResult(bytes);
        final backend = _RecordingCutoutBackend(autoResult);
        final centerIndex =
            (autoResult.mask.height ~/ 2) * autoResult.mask.width +
            autoResult.mask.width ~/ 2;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: bytes,
                  initialSourceImageName: 'Party Ship.PNG',
                  autoRunInitialCutout: true,
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: bytes,
                    thumbnailBytes: bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(backend.generateCount, 1);
        expect(backend.renderMasks, isEmpty);

        final previewGesture = find.descendant(
          of: find.bySemanticsLabel(
            'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
          ),
          matching: find.byType(GestureDetector),
        );
        await tester.tap(previewGesture);
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pump();

        expect(backend.renderMasks, hasLength(1));
        expect(
          backend.renderMasks.single.alpha[centerIndex],
          lessThan(autoResult.mask.alpha[centerIndex]),
        );

        await tester.tap(find.text('Reset'));
        await tester.pump();
        await tester.pump();

        expect(backend.renderMasks, hasLength(2));
        expect(
          backend.renderMasks.last.alpha[centerIndex],
          autoResult.mask.alpha[centerIndex],
        );
        expect(find.text('Auto mask restored.'), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'reset cancels a queued brush rerender',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bytes = _redSquareOnWhitePng();
        final autoResult = _syntheticCutoutResult(bytes);
        final backend = _RecordingCutoutBackend(autoResult);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: bytes,
                  initialSourceImageName: 'Party Ship.PNG',
                  autoRunInitialCutout: true,
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: bytes,
                    thumbnailBytes: bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await _pumpCreator(tester);

        final previewGesture = find.descendant(
          of: find.bySemanticsLabel(
            'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
          ),
          matching: find.byType(GestureDetector),
        );
        await tester.tap(previewGesture);
        await tester.pump();
        await tester.tap(find.text('Reset'));
        await _pumpCreator(tester);
        await tester.pump(const Duration(milliseconds: 250));

        expect(backend.renderMasks, hasLength(1));
        expect(find.text('Auto mask restored.'), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'restore brush rerenders an edited mask after erase',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bytes = _redSquareOnWhitePng();
        final autoResult = _syntheticCutoutResult(bytes);
        final backend = _RecordingCutoutBackend(autoResult);
        final centerIndex =
            (autoResult.mask.height ~/ 2) * autoResult.mask.width +
            autoResult.mask.width ~/ 2;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 700,
                height: 1200,
                child: EmoticonCreator(
                  initialSourceImageData: bytes,
                  initialSourceImageName: 'Party Ship.PNG',
                  autoRunInitialCutout: true,
                  cutoutService: ImageCutoutService(backend: backend),
                  draftStore: _FakeDraftStore(
                    draft: null,
                    pngBytes: bytes,
                    thumbnailBytes: bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final previewGesture = find.descendant(
          of: find.bySemanticsLabel(
            'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
          ),
          matching: find.byType(GestureDetector),
        );

        await tester.tap(previewGesture);
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pump();

        expect(backend.renderMasks, hasLength(1));
        final erasedAlpha = backend.renderMasks.single.alpha[centerIndex];
        expect(erasedAlpha, lessThan(autoResult.mask.alpha[centerIndex]));

        await tester.tap(find.widgetWithText(FilterChip, 'Restore'));
        await tester.pump();
        await tester.tap(previewGesture);
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pump();

        expect(backend.renderMasks, hasLength(2));
        expect(
          backend.renderMasks.last.alpha[centerIndex],
          greaterThan(erasedAlpha),
        );
        expect(find.text('Transparent PNG updated.'), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets('failed emoticon delete re-enables the editor', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var attempts = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              height: 1200,
              child: EmoticonCreator(
                onDelete: () async {
                  attempts++;
                  throw StateError('delete failed');
                },
              ),
            ),
          ),
        ),
      );
      await _pumpCreator(tester);

      await _tapVisible(tester, find.text('Delete'));
      await _tapVisible(tester, find.text('Yes'));

      expect(attempts, 1);
      expect(find.text('This emoticon could not be deleted.'), findsOneWidget);

      await _tapVisible(tester, find.text('Delete'));
      await _tapVisible(tester, find.text('Yes'));

      expect(attempts, 2);
    });

    testWidgets('renders unsupported state for a preloaded source', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bytes = _redSquareOnWhitePng();
      const message = 'Desktop ONNX background removal is not available yet.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              height: 1200,
              child: EmoticonCreator(
                initialSourceImageData: bytes,
                initialSourceImageName: 'Party Ship.PNG',
                autoRunInitialCutout: true,
                cutoutService: ImageCutoutService(
                  backend: const UnsupportedImageCutoutBackend(
                    backendType: ImageCutoutBackendType.onnxBackgroundRemoval,
                    failureCode: ImageCutoutFailureCode.modelNotAvailable,
                    message: message,
                  ),
                ),
                draftStore: _FakeDraftStore(
                  draft: null,
                  pngBytes: bytes,
                  thumbnailBytes: bytes,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await _pumpCreator(tester);

      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('Transparent PNG ready.'), findsNothing);

      final eraseChip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Erase'),
      );
      expect(eraseChip.onSelected, isNull);
    });

    testWidgets('declined pack save re-enables the editor', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var attempts = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              height: 400,
              child: EmoticonCreator(
                createPack: true,
                creatingNew: true,
                onCreate: (_, _, _) async {
                  attempts++;
                  return false;
                },
              ),
            ),
          ),
        ),
      );
      await _pumpCreator(tester);

      await tester.enterText(find.byType(EditableText), 'Beta Pack');
      await _tapVisible(tester, find.text('Save!'));

      expect(attempts, 1);
      expect(find.text('Save!'), findsOneWidget);
      expect(find.text('Save was not completed.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _tapVisible(tester, find.text('Save!'));

      expect(attempts, 2);
    });
  });
}

Future<void> _pumpCreator(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<void> _tapVisible(
  WidgetTester tester,
  Finder finder, {
  bool warnIfMissed = true,
}) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: warnIfMissed);
  await _pumpCreator(tester);
}

class _FakeDraftStore implements EmoticonDraftStore {
  _FakeDraftStore({
    required EmoticonDraft? draft,
    required Uint8List pngBytes,
    required Uint8List thumbnailBytes,
  }) : _draft = draft,
       _pngBytes = pngBytes,
       _thumbnailBytes = thumbnailBytes;

  EmoticonDraft? _draft;
  final Uint8List _pngBytes;
  final Uint8List _thumbnailBytes;
  final List<String> deletedIds = [];

  @override
  Future<EmoticonDraft> saveDraft({
    required String shortcode,
    required Uint8List pngBytes,
    required Uint8List thumbnailBytes,
    required ImageCutoutBackendType backend,
    required int width,
    required int height,
    String? sourceImageHash,
    String? packId,
    Uri? mxcUri,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<EmoticonDraft>> listDrafts() async {
    final draft = _draft;
    return draft == null ? const [] : [draft];
  }

  @override
  Future<EmoticonDraftData?> loadDraft(String id) async {
    final draft = _draft;
    if (draft == null || draft.id != id) {
      return null;
    }
    return EmoticonDraftData(
      draft: draft,
      pngBytes: _pngBytes,
      thumbnailBytes: _thumbnailBytes,
    );
  }

  @override
  Future<Uint8List?> readDraftPng(String id) async {
    return _draft?.id == id ? _pngBytes : null;
  }

  @override
  Future<Uint8List?> readDraftThumbnail(String id) async {
    return _draft?.id == id ? _thumbnailBytes : null;
  }

  @override
  Future<void> deleteDraft(String id) async {
    deletedIds.add(id);
    if (_draft?.id == id) {
      _draft = null;
    }
  }
}

EmoticonDraftData _draftData({
  required String id,
  required String shortcode,
  required Uint8List bytes,
  required DateTime createdAt,
  int width = 64,
  int height = 64,
}) {
  return EmoticonDraftData(
    draft: EmoticonDraft(
      id: id,
      shortcode: shortcode,
      outputPngPath: '$id.png',
      thumbnailPath: '$id-thumb.png',
      backend: ImageCutoutBackendType.localEdgeSegmentation,
      createdAt: createdAt,
      width: width,
      height: height,
      fileSize: bytes.length,
    ),
    pngBytes: bytes,
    thumbnailBytes: bytes,
  );
}

class _DraftRecordStore implements EmoticonDraftStore {
  _DraftRecordStore(List<EmoticonDraftData> drafts) : _drafts = List.of(drafts);

  final List<EmoticonDraftData> _drafts;
  final List<String> deletedIds = [];

  @override
  Future<EmoticonDraft> saveDraft({
    required String shortcode,
    required Uint8List pngBytes,
    required Uint8List thumbnailBytes,
    required ImageCutoutBackendType backend,
    required int width,
    required int height,
    String? sourceImageHash,
    String? packId,
    Uri? mxcUri,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<EmoticonDraft>> listDrafts() async {
    return _drafts.map((record) => record.draft).toList(growable: false);
  }

  @override
  Future<EmoticonDraftData?> loadDraft(String id) async {
    for (final record in _drafts) {
      if (record.draft.id == id) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<Uint8List?> readDraftPng(String id) async {
    return (await loadDraft(id))?.pngBytes;
  }

  @override
  Future<Uint8List?> readDraftThumbnail(String id) async {
    return (await loadDraft(id))?.thumbnailBytes;
  }

  @override
  Future<void> deleteDraft(String id) async {
    deletedIds.add(id);
    _drafts.removeWhere((record) => record.draft.id == id);
  }
}

class _SavedDraftRecord {
  const _SavedDraftRecord({
    required this.shortcode,
    required this.pngBytes,
    required this.thumbnailBytes,
    required this.backend,
    required this.width,
    required this.height,
    this.sourceImageHash,
    this.packId,
  });

  final String shortcode;
  final Uint8List pngBytes;
  final Uint8List thumbnailBytes;
  final ImageCutoutBackendType backend;
  final int width;
  final int height;
  final String? sourceImageHash;
  final String? packId;
}

class _SavingDraftStore implements EmoticonDraftStore {
  final savedDrafts = <_SavedDraftRecord>[];
  final _drafts = <EmoticonDraftData>[];
  void Function()? onSave;

  @override
  Future<EmoticonDraft> saveDraft({
    required String shortcode,
    required Uint8List pngBytes,
    required Uint8List thumbnailBytes,
    required ImageCutoutBackendType backend,
    required int width,
    required int height,
    String? sourceImageHash,
    String? packId,
    Uri? mxcUri,
  }) async {
    onSave?.call();
    final draft = EmoticonDraft(
      id: 'draft-${savedDrafts.length + 1}',
      shortcode: shortcode,
      outputPngPath: 'draft-${savedDrafts.length + 1}.png',
      thumbnailPath: 'draft-${savedDrafts.length + 1}-thumb.png',
      backend: backend,
      createdAt: DateTime.utc(2026, 7, 5, 18),
      width: width,
      height: height,
      fileSize: pngBytes.length,
      sourceImageHash: sourceImageHash,
      packId: packId,
      mxcUri: mxcUri?.toString(),
    );
    savedDrafts.add(
      _SavedDraftRecord(
        shortcode: shortcode,
        pngBytes: pngBytes,
        thumbnailBytes: thumbnailBytes,
        backend: backend,
        width: width,
        height: height,
        sourceImageHash: sourceImageHash,
        packId: packId,
      ),
    );
    _drafts.add(
      EmoticonDraftData(
        draft: draft,
        pngBytes: pngBytes,
        thumbnailBytes: thumbnailBytes,
      ),
    );
    return draft;
  }

  @override
  Future<List<EmoticonDraft>> listDrafts() async =>
      _drafts.map((record) => record.draft).toList(growable: false);

  @override
  Future<EmoticonDraftData?> loadDraft(String id) async {
    for (final record in _drafts) {
      if (record.draft.id == id) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<Uint8List?> readDraftPng(String id) async {
    return (await loadDraft(id))?.pngBytes;
  }

  @override
  Future<Uint8List?> readDraftThumbnail(String id) async {
    return (await loadDraft(id))?.thumbnailBytes;
  }

  @override
  Future<void> deleteDraft(String id) async {}
}

class _FakeEmoticonPack implements EmoticonPack {
  const _FakeEmoticonPack({required this.identifier});

  @override
  final String identifier;

  @override
  String get attribution => '';

  @override
  String get displayName => 'Personal pack';

  @override
  String get ownerId => '@user:example.org';

  @override
  String get ownerDisplayName => 'User';

  @override
  bool get isGloballyAvailable => false;

  @override
  List<Emoticon> get emotes => const [];

  @override
  List<Emoticon> get emoji => const [];

  @override
  List<Emoticon> get stickers => const [];

  @override
  List<String> getShortcodes() => const [];

  @override
  ImageProvider? get image => null;

  @override
  IconData? get icon => null;

  @override
  EmoticonUsage get usage => EmoticonUsage.all;

  @override
  bool get isStickerPack => true;

  @override
  bool get isEmojiPack => true;

  @override
  Emoticon? getByShortcode(String shortcode) => null;

  @override
  Future<void> deleteEmoticon(Emoticon emoticon) async {}

  @override
  Future<void> setPackUsage(EmoticonUsage usage) async {}

  @override
  Future<void> updatePack({
    EmoticonUsage? usage,
    String? name,
    Uint8List? imageData,
  }) async {}

  @override
  Future<void> updateEmoticon({
    String? slug,
    String? shortcode,
    Uint8List? data,
    String? mimeType,
    EmoticonUsage? usage,
    required Emoticon previous,
  }) async {}

  @override
  Future<void> addEmoticon({
    required String slug,
    String? shortcode,
    required Uint8List data,
    String? mimeType,
    EmoticonUsage usage = EmoticonUsage.emoji,
  }) async {}

  @override
  Future<void> markAsGlobal(bool isGlobal) async {}
}

class _FakePickerResult implements PickerResult {
  const _FakePickerResult(this.bytes, {required this.name});

  final Uint8List bytes;

  @override
  final String name;

  @override
  String? get mimeType => 'image/png';

  @override
  Future<Uint8List> readAsBytes() async => bytes;
}

class _ThrowingPickerResult implements PickerResult {
  const _ThrowingPickerResult(this.name);

  @override
  final String name;

  @override
  String? get mimeType => 'image/png';

  @override
  Future<Uint8List> readAsBytes() async {
    throw StateError('picker read failed');
  }
}

class _DeferredCutoutBackend implements ImageCutoutBackend {
  _DeferredCutoutBackend();

  final Completer<CutoutResult> _completer = Completer<CutoutResult>();

  void complete(CutoutResult result) {
    _completer.complete(result);
  }

  @override
  ImageCutoutBackendType get type =>
      ImageCutoutBackendType.localEdgeSegmentation;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) {
    return _completer.future;
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) {
    return _completer.future;
  }
}

class _DeferredRenderCutoutBackend implements ImageCutoutBackend {
  _DeferredRenderCutoutBackend(this.result);

  final CutoutResult result;
  final renderMasks = <CutoutMask>[];
  Completer<CutoutResult>? _renderCompleter;
  int generateCount = 0;

  @override
  ImageCutoutBackendType get type =>
      ImageCutoutBackendType.localEdgeSegmentation;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    generateCount++;
    return result;
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) {
    renderMasks.add(mask);
    final completer = Completer<CutoutResult>();
    _renderCompleter = completer;
    return completer.future;
  }

  void completeRender() {
    final completer = _renderCompleter;
    if (completer == null || completer.isCompleted || renderMasks.isEmpty) {
      return;
    }
    completer.complete(result.copyWith(mask: renderMasks.last));
  }
}

class _ThrowingCutoutBackend implements ImageCutoutBackend {
  _ThrowingCutoutBackend({
    this.generateResult,
    this.generateException,
    this.renderException,
  });

  final CutoutResult? generateResult;
  final ImageCutoutException? generateException;
  final ImageCutoutException? renderException;
  int generateCount = 0;
  int renderCount = 0;

  @override
  ImageCutoutBackendType get type =>
      ImageCutoutBackendType.localEdgeSegmentation;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    generateCount++;
    final exception = generateException;
    if (exception != null) {
      throw exception;
    }
    final result = generateResult;
    if (result != null) {
      return result;
    }
    throw const ImageCutoutException(
      ImageCutoutFailureCode.processingFailed,
      'Generate failed.',
    );
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) async {
    renderCount++;
    final exception = renderException;
    if (exception != null) {
      throw exception;
    }
    final result = generateResult;
    if (result != null) {
      return result.copyWith(mask: mask);
    }
    throw const ImageCutoutException(
      ImageCutoutFailureCode.processingFailed,
      'Render failed.',
    );
  }
}

class _RecordingCutoutBackend implements ImageCutoutBackend {
  _RecordingCutoutBackend(this.result);

  final CutoutResult result;
  final renderMasks = <CutoutMask>[];
  int generateCount = 0;

  @override
  ImageCutoutBackendType get type =>
      ImageCutoutBackendType.localEdgeSegmentation;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    generateCount++;
    return result;
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) async {
    renderMasks.add(mask);
    return result.copyWith(mask: mask);
  }
}

Uint8List _redSquareOnWhitePng() {
  final image = img.Image(width: 64, height: 64, numChannels: 4)
    ..clear(img.ColorRgba8(255, 255, 255, 255));

  for (var y = 20; y < 44; y++) {
    for (var x = 20; x < 44; x++) {
      image.setPixelRgba(x, y, 230, 30, 20, 255);
    }
  }

  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _blueCircleTransparentPng() {
  final image = img.Image(width: 64, height: 64, numChannels: 4)
    ..clear(img.ColorRgba8(0, 0, 0, 0));

  for (var y = 16; y < 48; y++) {
    for (var x = 16; x < 48; x++) {
      final dx = x - 32;
      final dy = y - 32;
      if (dx * dx + dy * dy <= 16 * 16) {
        image.setPixelRgba(x, y, 30, 80, 240, 255);
      }
    }
  }

  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _wideSubjectPng() {
  final image = img.Image(width: 64, height: 32, numChannels: 4)
    ..clear(img.ColorRgba8(0, 0, 0, 0));

  for (var y = 8; y < 24; y++) {
    for (var x = 20; x < 44; x++) {
      image.setPixelRgba(x, y, 30, 80, 240, 255);
    }
  }

  return Uint8List.fromList(img.encodePng(image));
}

CutoutResult _syntheticCutoutResult(Uint8List bytes) {
  return CutoutResult(
    pngBytes: bytes,
    thumbnailBytes: bytes,
    mask: _centerSubjectMask(),
    backend: ImageCutoutBackendType.localEdgeSegmentation,
    subjectBounds: const CutoutIntRect(
      left: 20,
      top: 20,
      right: 43,
      bottom: 43,
    ),
    cropBounds: const CutoutIntRect(left: 0, top: 0, right: 63, bottom: 63),
    sourceWidth: 64,
    sourceHeight: 64,
    width: 64,
    height: 64,
    processingDuration: Duration.zero,
  );
}

CutoutResult _syntheticWideCutoutResult(Uint8List bytes) {
  return CutoutResult(
    pngBytes: bytes,
    thumbnailBytes: bytes,
    mask: _wideCenterSubjectMask(),
    backend: ImageCutoutBackendType.localEdgeSegmentation,
    subjectBounds: const CutoutIntRect(left: 20, top: 8, right: 43, bottom: 23),
    cropBounds: const CutoutIntRect(left: 0, top: 0, right: 63, bottom: 31),
    sourceWidth: 64,
    sourceHeight: 32,
    width: 64,
    height: 32,
    processingDuration: Duration.zero,
  );
}

CutoutMask _centerSubjectMask() {
  final alpha = Uint8List(64 * 64);
  for (var y = 20; y < 44; y++) {
    for (var x = 20; x < 44; x++) {
      alpha[y * 64 + x] = 255;
    }
  }
  return CutoutMask(width: 64, height: 64, alpha: alpha);
}

CutoutMask _wideCenterSubjectMask() {
  final alpha = Uint8List(64 * 32);
  for (var y = 8; y < 24; y++) {
    for (var x = 20; x < 44; x++) {
      alpha[y * 64 + x] = 255;
    }
  }
  return CutoutMask(width: 64, height: 32, alpha: alpha);
}

Uint8List _solidWhitePng() {
  final image = img.Image(width: 64, height: 64, numChannels: 4)
    ..clear(img.ColorRgba8(255, 255, 255, 255));

  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _largeRedSquareOnWhitePng() {
  final image = img.Image(width: 400, height: 320, numChannels: 4)
    ..clear(img.ColorRgba8(255, 255, 255, 255));

  for (var y = 110; y < 210; y++) {
    for (var x = 150; x < 250; x++) {
      image.setPixelRgba(x, y, 230, 30, 20, 255);
    }
  }

  return Uint8List.fromList(img.encodePng(image));
}

List<String> _pngChunkTypes(Uint8List pngBytes) {
  const signatureLength = 8;
  final types = <String>[];
  var offset = signatureLength;

  while (offset + 12 <= pngBytes.length) {
    final length =
        (pngBytes[offset] << 24) |
        (pngBytes[offset + 1] << 16) |
        (pngBytes[offset + 2] << 8) |
        pngBytes[offset + 3];
    final type = String.fromCharCodes(pngBytes.sublist(offset + 4, offset + 8));
    types.add(type);
    offset += 12 + length;
    if (type == 'IEND') {
      break;
    }
  }

  return types;
}
