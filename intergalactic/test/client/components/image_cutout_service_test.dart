import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('ImageCutoutService', () {
    test('feathers edges without losing transparent background', () async {
      final service = ImageCutoutService();
      final result = await service.generate(
        imageBytes: _redSquareOnWhitePng(),
        settings: const CutoutSettings(
          edgeSoftness: 3,
          paddingFraction: 0.08,
          maxProcessingDimension: 64,
          maxOutputDimension: 64,
        ),
      );

      expect(result.backend, ImageCutoutBackendType.localEdgeSegmentation);
      expect(transparentPngHasAlpha(result.pngBytes), isTrue);

      final decoded = img.decodePng(result.pngBytes)!;
      final alphaValues = decoded.map((pixel) => pixel.a.round()).toList();
      expect(alphaValues.any((alpha) => alpha == 0), isTrue);
      expect(alphaValues.any((alpha) => alpha > 0 && alpha < 255), isTrue);
      expect(alphaValues.any((alpha) => alpha > 220), isTrue);
    });

    test('edge offset expands and contracts generated mask bounds', () async {
      final service = ImageCutoutService();
      final sourceBytes = _redSquareOnWhitePng();
      const baseSettings = CutoutSettings(
        edgeSoftness: 0,
        paddingFraction: 0.08,
        squareCanvas: false,
        maxProcessingDimension: 64,
        maxOutputDimension: 64,
      );

      final base = await service.generate(
        imageBytes: sourceBytes,
        settings: baseSettings,
      );
      final expanded = await service.generate(
        imageBytes: sourceBytes,
        settings: baseSettings.copyWith(edgeExpansion: 3),
      );
      final contracted = await service.generate(
        imageBytes: sourceBytes,
        settings: baseSettings.copyWith(edgeExpansion: -3),
      );

      expect(
        expanded.subjectBounds.width,
        greaterThan(base.subjectBounds.width),
      );
      expect(
        expanded.subjectBounds.height,
        greaterThan(base.subjectBounds.height),
      );
      expect(
        contracted.subjectBounds.width,
        lessThan(base.subjectBounds.width),
      );
      expect(
        contracted.subjectBounds.height,
        lessThan(base.subjectBounds.height),
      );
      expect(transparentPngHasAlpha(expanded.pngBytes), isTrue);
      expect(transparentPngHasAlpha(contracted.pngBytes), isTrue);
    });

    test('renders square and tight crop canvas modes', () async {
      final service = ImageCutoutService();
      final sourceBytes = _wideSubjectOnWhitePng();
      const baseSettings = CutoutSettings(
        edgeSoftness: 0,
        paddingFraction: 0.08,
        maxProcessingDimension: 64,
        maxOutputDimension: 64,
      );

      final square = await service.generate(
        imageBytes: sourceBytes,
        settings: baseSettings.copyWith(squareCanvas: true),
      );
      final tight = await service.generate(
        imageBytes: sourceBytes,
        settings: baseSettings.copyWith(squareCanvas: false),
      );

      expect(square.width, square.height);
      expect(tight.width, greaterThan(tight.height));
      expect(tight.height, lessThan(square.height));
      expect(transparentPngHasAlpha(square.pngBytes), isTrue);
      expect(transparentPngHasAlpha(tight.pngBytes), isTrue);
    });

    test('bakes EXIF orientation before segmentation', () async {
      final service = ImageCutoutService();
      final result = await service.generate(
        imageBytes: _wideSubjectWithExifOrientationJpg(),
        settings: const CutoutSettings(
          edgeSoftness: 0,
          paddingFraction: 0.08,
          squareCanvas: false,
          maxProcessingDimension: 64,
          maxOutputDimension: 64,
        ),
      );

      expect(result.backend, ImageCutoutBackendType.localEdgeSegmentation);
      expect(result.sourceWidth, 40);
      expect(result.sourceHeight, 64);
      expect(
        result.subjectBounds.height,
        greaterThan(result.subjectBounds.width),
      );
      expect(result.height, greaterThan(result.width));
      expect(transparentPngHasAlpha(result.pngBytes), isTrue);
    });

    test('emits structured diagnostics for generate and render', () async {
      final events = <ImageCutoutDiagnosticEvent>[];
      final service = ImageCutoutService(
        hostPlatform: ImageCutoutHostPlatform.desktop,
        onDiagnostics: events.add,
      );
      final sourceBytes = _redSquareOnWhitePng();
      const settings = CutoutSettings(
        edgeSoftness: 0,
        maxProcessingDimension: 64,
        maxOutputDimension: 64,
      );

      final generated = await service.generate(
        imageBytes: sourceBytes,
        settings: settings,
      );
      await service.render(
        imageBytes: sourceBytes,
        mask: generated.mask,
        settings: settings,
      );

      expect(events, hasLength(2));

      final generateEvent = events[0];
      expect(generateEvent.operation, ImageCutoutOperation.generate);
      expect(generateEvent.hostPlatform, ImageCutoutHostPlatform.desktop);
      expect(
        generateEvent.preferredBackend,
        ImageCutoutBackendType.onnxBackgroundRemoval,
      );
      expect(
        generateEvent.selectedBackend,
        ImageCutoutBackendType.localEdgeSegmentation,
      );
      expect(
        generateEvent.backend,
        ImageCutoutBackendType.localEdgeSegmentation,
      );
      expect(generateEvent.usesFallback, isTrue);
      expect(generateEvent.preferredBackendAvailable, isFalse);
      expect(generateEvent.selectedBackendAvailable, isTrue);
      expect(generateEvent.requiresModelArtifact, isFalse);
      expect(generateEvent.success, isTrue);
      expect(generateEvent.failureCode, isNull);
      expect(generateEvent.inputByteCount, sourceBytes.length);
      expect(generateEvent.sourceWidth, 64);
      expect(generateEvent.sourceHeight, 64);
      expect(generateEvent.outputWidth, generated.width);
      expect(generateEvent.outputHeight, generated.height);
      expect(generateEvent.maskWidth, generated.mask.width);
      expect(generateEvent.maskHeight, generated.mask.height);
      expect(generateEvent.outputPngByteCount, generated.pngBytes.length);
      expect(generateEvent.thumbnailByteCount, generated.thumbnailBytes.length);

      final renderEvent = events[1];
      expect(renderEvent.operation, ImageCutoutOperation.render);
      expect(renderEvent.success, isTrue);
      expect(renderEvent.maskWidth, generated.mask.width);
      expect(renderEvent.maskHeight, generated.mask.height);
      expect(renderEvent.inputByteCount, sourceBytes.length);
    });

    test(
      'registered native backend uses platform mask and shared renderer',
      () async {
        final platform = _FakeImageCutoutPlatform(_centerSubjectMask());
        final service = ImageCutoutService(
          hostPlatform: ImageCutoutHostPlatform.apple,
          registeredBackends: const {
            ImageCutoutBackendType.appleVisionSubjectLift,
          },
          platform: platform,
        );

        expect(
          service.selection.preferredType,
          ImageCutoutBackendType.appleVisionSubjectLift,
        );
        expect(
          service.selection.selectedType,
          ImageCutoutBackendType.appleVisionSubjectLift,
        );
        expect(service.selection.usesFallback, isFalse);

        final settings = const CutoutSettings(
          backgroundTolerance: 17,
          edgeSoftness: 0,
          paddingFraction: 0.08,
          maxProcessingDimension: 64,
          maxOutputDimension: 64,
        );
        final result = await service.generate(
          imageBytes: _redSquareOnWhitePng(),
          settings: settings,
        );

        expect(result.backend, ImageCutoutBackendType.appleVisionSubjectLift);
        expect(transparentPngHasAlpha(result.pngBytes), isTrue);
        expect(platform.requests, hasLength(1));
        expect(
          platform.requests.single.backendType,
          ImageCutoutBackendType.appleVisionSubjectLift,
        );
        expect(platform.requests.single.settings.backgroundTolerance, 17);
      },
    );

    test(
      'Android runtime registers ML Kit native backend by default',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
        });

        final platform = _FakeImageCutoutPlatform(_centerSubjectMask());
        final service = ImageCutoutService(platform: platform);

        expect(
          ImageCutoutBackendSelector.defaultRegisteredBackendsForRuntime(),
          contains(ImageCutoutBackendType.androidMlKitSubjectSegmentation),
        );
        expect(
          service.selection.preferredType,
          ImageCutoutBackendType.androidMlKitSubjectSegmentation,
        );
        expect(
          service.selection.selectedType,
          ImageCutoutBackendType.androidMlKitSubjectSegmentation,
        );
        expect(service.selection.usesFallback, isFalse);

        final result = await service.generate(
          imageBytes: _redSquareOnWhitePng(),
          settings: const CutoutSettings(
            edgeSoftness: 0,
            maxProcessingDimension: 64,
            maxOutputDimension: 64,
          ),
        );

        expect(
          result.backend,
          ImageCutoutBackendType.androidMlKitSubjectSegmentation,
        );
        expect(
          platform.requests.single.backendType,
          ImageCutoutBackendType.androidMlKitSubjectSegmentation,
        );
        expect(transparentPngHasAlpha(result.pngBytes), isTrue);
      },
    );

    test('native platform failure remains structured', () async {
      final service = ImageCutoutService(
        hostPlatform: ImageCutoutHostPlatform.android,
        allowLocalFallback: false,
        registeredBackends: const {
          ImageCutoutBackendType.androidMlKitSubjectSegmentation,
        },
        platform: const _FailingImageCutoutPlatform(
          ImageCutoutFailureCode.modelDownloadRequired,
        ),
      );

      await expectLater(
        service.generate(imageBytes: _redSquareOnWhitePng()),
        throwsA(
          isA<ImageCutoutException>().having(
            (error) => error.code,
            'code',
            ImageCutoutFailureCode.modelDownloadRequired,
          ),
        ),
      );
    });

    test('emits structured diagnostics for unsupported failures', () async {
      final events = <ImageCutoutDiagnosticEvent>[];
      final service = ImageCutoutService(
        backend: const UnsupportedImageCutoutBackend(),
        onDiagnostics: events.add,
      );
      final sourceBytes = _redSquareOnWhitePng();

      await expectLater(
        service.generate(imageBytes: sourceBytes),
        throwsA(
          isA<ImageCutoutException>().having(
            (error) => error.code,
            'code',
            ImageCutoutFailureCode.unsupportedPlatform,
          ),
        ),
      );

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.operation, ImageCutoutOperation.generate);
      expect(event.backend, ImageCutoutBackendType.unsupported);
      expect(event.selectedBackend, ImageCutoutBackendType.unsupported);
      expect(event.success, isFalse);
      expect(event.failureCode, ImageCutoutFailureCode.unsupportedPlatform);
      expect(event.inputByteCount, sourceBytes.length);
      expect(event.sourceWidth, isNull);
      expect(event.outputPngByteCount, isNull);
    });

    test('renders an edited erase-mask into the exported PNG', () async {
      final service = ImageCutoutService();
      final sourceBytes = _redSquareOnWhitePng();
      final settings = const CutoutSettings(
        edgeSoftness: 0,
        paddingFraction: 0.08,
        maxProcessingDimension: 64,
        maxOutputDimension: 64,
      );
      final original = await service.generate(
        imageBytes: sourceBytes,
        settings: settings,
      );
      final erasedMask = original.mask.applyBrush(
        normalizedX: 0.5,
        normalizedY: 0.5,
        radiusFraction: 0.14,
        mode: CutoutBrushMode.erase,
      );

      final erased = await service.render(
        imageBytes: sourceBytes,
        mask: erasedMask,
        settings: settings,
      );

      final originalImage = img.decodePng(original.pngBytes)!;
      final erasedImage = img.decodePng(erased.pngBytes)!;
      final originalCenter = originalImage.getPixel(
        originalImage.width ~/ 2,
        originalImage.height ~/ 2,
      );
      final erasedCenter = erasedImage.getPixel(
        erasedImage.width ~/ 2,
        erasedImage.height ~/ 2,
      );

      expect(erased.width, original.width);
      expect(erased.height, original.height);
      expect(originalCenter.a, greaterThan(220));
      expect(erasedCenter.a, lessThan(originalCenter.a));
    });

    test('restore brush raises alpha after an erase edit', () async {
      final service = ImageCutoutService();
      final original = await service.generate(
        imageBytes: _redSquareOnWhitePng(),
        settings: const CutoutSettings(
          edgeSoftness: 0,
          maxProcessingDimension: 64,
          maxOutputDimension: 64,
        ),
      );
      final centerIndex =
          (original.mask.height ~/ 2) * original.mask.width +
          original.mask.width ~/ 2;
      final erased = original.mask.applyBrush(
        normalizedX: 0.5,
        normalizedY: 0.5,
        radiusFraction: 0.14,
        mode: CutoutBrushMode.erase,
      );
      final restored = erased.applyBrush(
        normalizedX: 0.5,
        normalizedY: 0.5,
        radiusFraction: 0.14,
        mode: CutoutBrushMode.restore,
      );

      expect(original.mask.alpha[centerIndex], greaterThan(220));
      expect(
        erased.alpha[centerIndex],
        lessThan(original.mask.alpha[centerIndex]),
      );
      expect(
        restored.alpha[centerIndex],
        greaterThan(erased.alpha[centerIndex]),
      );
    });

    test(
      'returns no-subject failure when refinement erases foreground',
      () async {
        final service = ImageCutoutService();
        final sourceBytes = _redSquareOnWhitePng();
        final settings = const CutoutSettings(
          edgeSoftness: 0,
          maxProcessingDimension: 64,
          maxOutputDimension: 64,
        );
        final original = await service.generate(
          imageBytes: sourceBytes,
          settings: settings,
        );
        final erasedMask = CutoutMask(
          width: original.mask.width,
          height: original.mask.height,
          alpha: Uint8List(original.mask.alpha.length),
        );

        await expectLater(
          service.render(
            imageBytes: sourceBytes,
            mask: erasedMask,
            settings: settings,
          ),
          throwsA(
            isA<ImageCutoutException>().having(
              (error) => error.code,
              'code',
              ImageCutoutFailureCode.noSubjectFound,
            ),
          ),
        );
      },
    );
  });
}

class _FailingImageCutoutPlatform implements ImageCutoutPlatform {
  const _FailingImageCutoutPlatform(this.code);

  final ImageCutoutFailureCode code;

  @override
  Future<CutoutMask> generateMask({
    required ImageCutoutBackendType backendType,
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    throw ImageCutoutException(code, 'Native test failure.');
  }
}

class _FakeImageCutoutPlatform implements ImageCutoutPlatform {
  _FakeImageCutoutPlatform(this.mask);

  final CutoutMask mask;
  final requests = <_FakeImageCutoutRequest>[];

  @override
  Future<CutoutMask> generateMask({
    required ImageCutoutBackendType backendType,
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    requests.add(
      _FakeImageCutoutRequest(
        backendType: backendType,
        imageBytes: imageBytes,
        settings: settings,
      ),
    );
    return mask;
  }
}

class _FakeImageCutoutRequest {
  const _FakeImageCutoutRequest({
    required this.backendType,
    required this.imageBytes,
    required this.settings,
  });

  final ImageCutoutBackendType backendType;
  final Uint8List imageBytes;
  final CutoutSettings settings;
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

Uint8List _wideSubjectOnWhitePng() {
  final image = img.Image(width: 64, height: 64, numChannels: 4)
    ..clear(img.ColorRgba8(255, 255, 255, 255));

  for (var y = 26; y < 38; y++) {
    for (var x = 12; x < 52; x++) {
      image.setPixelRgba(x, y, 20, 120, 230, 255);
    }
  }

  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _wideSubjectWithExifOrientationJpg() {
  final image = img.Image(width: 64, height: 40, numChannels: 3)
    ..clear(img.ColorRgb8(255, 255, 255));

  for (var y = 16; y < 24; y++) {
    for (var x = 12; x < 52; x++) {
      image.setPixelRgb(x, y, 20, 120, 230);
    }
  }

  image.exif.imageIfd.orientation = 6;
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
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
