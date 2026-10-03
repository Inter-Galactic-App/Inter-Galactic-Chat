import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/image_utils.dart';

/// A 1x1 transparent PNG.
final Uint8List _onePixelPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0B,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x60,
  0x00,
  0x02,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x7A,
  0x5E,
  0xAB,
  0x3F,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// A provider whose load never completes.
class _StalledImageProvider extends ImageProvider<_StalledImageProvider> {
  @override
  Future<_StalledImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _StalledImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

/// A provider whose load fails.
class _FailingImageProvider extends ImageProvider<_FailingImageProvider> {
  @override
  Future<_FailingImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future<ImageInfo>.error(StateError('media unavailable')),
  );
}

void main() {
  testWidgets('resolves a decodable image to its first frame', (tester) async {
    // Real decoding runs outside the test's fake clock.
    await tester.runAsync(() async {
      final ui.Image image = await ImageUtils.imageProviderToImage(
        MemoryImage(_onePixelPng),
      );
      expect(image.width, 1);
      expect(image.height, 1);
      image.dispose();
    });
  });

  testWidgets('a failed load completes with the error instead of hanging', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await expectLater(
        ImageUtils.imageProviderToImage(_FailingImageProvider()),
        throwsA(isA<StateError>()),
      );
    });
  });

  testWidgets('a stalled load times out when asked to', (tester) async {
    await tester.runAsync(() async {
      await expectLater(
        ImageUtils.imageProviderToImage(
          _StalledImageProvider(),
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  testWidgets('a stalled load without a timeout stays pending', (tester) async {
    // The pre-existing contract for callers that did not ask for a bound.
    var settled = false;
    final future = ImageUtils.imageProviderToImage(
      _StalledImageProvider(),
    ).then((_) => settled = true, onError: (_) => settled = true);
    await tester.pump(const Duration(seconds: 1));
    expect(settled, isFalse);
    // Not awaited: it never completes by construction.
    unawaited(future);
  });
}
