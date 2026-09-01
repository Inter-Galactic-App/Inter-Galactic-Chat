import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/emoticon_editor_controller.dart';

import 'emoticon_test_fixtures.dart';

void main() {
  EmoticonEditorController buildController({
    ImageCutoutBackend? backend,
    FakeDraftStore? store,
    EmoticonSaveToPhotosCallback? onSaveToPhotos,
  }) {
    return EmoticonEditorController(
      cutoutService: ImageCutoutService(
        backend:
            backend ??
            RecordingCutoutBackend(
              syntheticCutoutResult(redSquareOnWhitePng()),
            ),
      ),
      draftStore: store ?? FakeDraftStore(),
      creatingNew: true,
      onSaveToPhotos: onSaveToPhotos,
    );
  }

  test('initializes brush, cutout, and output defaults', () {
    final controller = buildController();
    addTearDown(controller.dispose);

    expect(controller.brushRadius, 0.05);
    expect(controller.brushStrength, 1.0);
    expect(controller.brushMode, CutoutBrushMode.erase);
    expect(controller.cutoutSettings, const CutoutSettings());
    expect(controller.previewBackground, CutoutPreviewBackground.checkerboard);
    expect(controller.activeToolGroup, isNull);
  });

  test('mutating a setting notifies listeners once per change', () {
    final controller = buildController();
    addTearDown(controller.dispose);

    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.setBrushRadius(0.08);
    expect(notifications, 1);

    // Setting the same value again does not notify.
    controller.setBrushRadius(0.08);
    expect(notifications, 1);

    controller.setBrushMode(CutoutBrushMode.restore);
    expect(notifications, 2);
  });

  test('tool group toggle opens one tray and closes on re-toggle', () {
    final controller = buildController();
    addTearDown(controller.dispose);

    controller.toggleToolGroup(EmoticonToolGroup.cutout);
    expect(controller.activeToolGroup, EmoticonToolGroup.cutout);

    controller.toggleToolGroup(EmoticonToolGroup.brush);
    expect(controller.activeToolGroup, EmoticonToolGroup.brush);

    controller.toggleToolGroup(EmoticonToolGroup.brush);
    expect(controller.activeToolGroup, isNull);
  });

  test('auto cutout runs through the shared engine path', () async {
    final backend = RecordingCutoutBackend(
      syntheticCutoutResult(redSquareOnWhitePng()),
    );
    final controller = buildController(backend: backend);
    addTearDown(controller.dispose);

    controller.setSourceImage(redSquareOnWhitePng());
    await controller.runAutoCutout();

    expect(backend.generateCount, 1);
    expect(controller.cutoutResult, isNotNull);
    expect(controller.imageData, isNotNull);
    expect(controller.statusText, contains('Transparent PNG ready.'));
  });

  test('drops an auto-cutout result after the source is replaced', () async {
    final backend = DeferredGenerateCutoutBackend();
    final controller = buildController(backend: backend);
    addTearDown(controller.dispose);

    controller.setSourceImage(redSquareOnWhitePng());
    final cutout = controller.runAutoCutout();
    expect(backend.generateCount, 1);

    final replacement = Uint8List.fromList(redSquareOnWhitePng());
    controller.setSourceImage(replacement);
    backend.complete(syntheticCutoutResult(redSquareOnWhitePng()));
    await cutout;

    expect(identical(controller.sourceImageData, replacement), isTrue);
    expect(controller.cutoutResult, isNull);
    expect(controller.imageData, isNull);
    expect(controller.loading, isFalse);
    expect(controller.processingCutout, isFalse);
  });

  test('drops a rerender result after the source is replaced', () async {
    final backend = DeferredRenderCutoutBackend(
      syntheticCutoutResult(redSquareOnWhitePng()),
    );
    final controller = buildController(backend: backend);
    addTearDown(controller.dispose);

    controller.setSourceImage(redSquareOnWhitePng());
    await controller.runAutoCutout();
    final rerender = controller.rerenderCutout();
    expect(backend.renderCount, 1);

    final replacement = Uint8List.fromList(redSquareOnWhitePng());
    controller.setSourceImage(replacement);
    backend.completeRender();
    await rerender;

    expect(identical(controller.sourceImageData, replacement), isTrue);
    expect(controller.cutoutResult, isNull);
    expect(controller.imageData, isNull);
    expect(controller.processingCutout, isFalse);
  });

  test('discarding an edit session drops a pending rerender', () async {
    final backend = DeferredRenderCutoutBackend(
      syntheticCutoutResult(redSquareOnWhitePng()),
    );
    final controller = buildController(backend: backend);
    addTearDown(controller.dispose);

    controller.setSourceImage(redSquareOnWhitePng());
    final originalSettings = controller.cutoutSettings;

    controller.beginEditSession();
    await controller.runAutoCutout();
    controller.updateCutoutSettings(
      controller.cutoutSettings.copyWith(outlineWidth: 4),
    );
    final rerender = controller.rerenderCutout();
    expect(backend.renderCount, 1);

    controller.discardEditSession();
    backend.completeRender();
    await rerender;

    expect(controller.cutoutResult, isNull);
    expect(controller.imageData, isNull);
    expect(controller.cutoutSettings, originalSettings);
    expect(controller.processingCutout, isFalse);
  });

  test('committing an edit session keeps the shaped image', () async {
    final controller = buildController();
    addTearDown(controller.dispose);

    controller.setSourceImage(redSquareOnWhitePng());
    controller.beginEditSession();
    await controller.runAutoCutout();
    controller.commitEditSession();

    expect(controller.cutoutResult, isNotNull);
    expect(controller.imageData, isNotNull);
  });

  test('saves only the generated cutout PNG to Photos', () async {
    String? filename;
    Uint8List? savedBytes;
    final controller = buildController(
      onSaveToPhotos: (name, data) async {
        filename = name;
        savedBytes = data;
        return true;
      },
    );
    addTearDown(controller.dispose);

    controller.setSourceImage(
      redSquareOnWhitePng(),
      name: 'Party Ship.PNG',
      seedShortcode: true,
    );
    await controller.runAutoCutout();

    final saved = await controller.saveCutoutToPhotos();

    expect(saved, isTrue);
    expect(filename, 'party_ship.png');
    expect(savedBytes, controller.cutoutResult!.pngBytes);
    expect(controller.statusText, 'Saved cutout to Photos.');
  });

  test('save falls back to the raw source photo without a cutout', () async {
    final store = FakeDraftStore();
    String? savedName;
    var savedBytesNonNull = false;
    final controller = EmoticonEditorController(
      cutoutService: ImageCutoutService(
        backend: RecordingCutoutBackend(
          syntheticCutoutResult(redSquareOnWhitePng()),
        ),
      ),
      draftStore: store,
      creatingNew: true,
      onCreate: (name, usage, data) async {
        savedName = name;
        savedBytesNonNull = data != null;
        return true;
      },
    );
    addTearDown(controller.dispose);

    controller.setSourceImage(redSquareOnWhitePng(), name: 'Party Ship.PNG');
    controller.shortcodeController.text = 'party_ship';

    final didSave = await controller.save();

    expect(didSave, isTrue);
    expect(savedName, 'party_ship');
    expect(savedBytesNonNull, isTrue);
    // No cutout was generated, so no local draft is written.
    expect(store.savedShortcodes, isEmpty);
  });

  test('invalid shortcode blocks save and surfaces the message', () async {
    final controller = buildController();
    addTearDown(controller.dispose);

    controller.setSourceImage(redSquareOnWhitePng());
    controller.shortcodeController.text = '';

    final didSave = await controller.save();

    expect(didSave, isFalse);
    expect(controller.errorText, isNotNull);
  });

  test('seeds shortcode from the picked image file name', () {
    expect(
      EmoticonEditorController.shortcodeSeedFromImageName('Party Ship.PNG'),
      'party_ship',
    );
    expect(
      EmoticonEditorController.shortcodeSeedFromImageName(
        r'C:\photos\Cool--Cat.jpeg',
      ),
      'cool_cat',
    );
  });
}

class DeferredGenerateCutoutBackend implements ImageCutoutBackend {
  final Completer<CutoutResult> _completer = Completer<CutoutResult>();
  int generateCount = 0;

  @override
  ImageCutoutBackendType get type =>
      ImageCutoutBackendType.localEdgeSegmentation;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) {
    generateCount++;
    return _completer.future;
  }

  void complete(CutoutResult result) => _completer.complete(result);

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) {
    throw UnimplementedError();
  }
}

class DeferredRenderCutoutBackend implements ImageCutoutBackend {
  DeferredRenderCutoutBackend(this.result);

  final CutoutResult result;
  final Completer<void> _renderGate = Completer<void>();
  int renderCount = 0;

  @override
  ImageCutoutBackendType get type =>
      ImageCutoutBackendType.localEdgeSegmentation;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    return result;
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) async {
    renderCount++;
    await _renderGate.future;
    return result.copyWith(mask: mask);
  }

  void completeRender() => _renderGate.complete();
}
