import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intergalactic/ui/molecules/favorite_rooms_list.dart';

void main() {
  group('favorites banner image normalization', () {
    test('compresses large iPhone-style crops to preference-safe bytes', () {
      final source = _solidPng(
        width: 4032,
        height: 1324,
        color: img.ColorRgb8(220, 120, 80),
      );

      final normalized = normalizeFavoritesBannerImageBytes(source);
      final encoded = base64Encode(normalized);
      final decoded = img.decodeImage(normalized);

      expect(
          encoded.length, lessThanOrEqualTo(favoritesBannerMaxPreferenceChars));
      expect(normalized.length, lessThan(source.length));
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(1400));
      expect(decoded.height, lessThanOrEqualTo(460));
    });

    test('reports base64 length without allocating encoded text', () {
      expect(favoritesBannerBase64LengthForBytes(0), 0);
      expect(favoritesBannerBase64LengthForBytes(1), 4);
      expect(favoritesBannerBase64LengthForBytes(2), 4);
      expect(favoritesBannerBase64LengthForBytes(3), 4);
      expect(favoritesBannerBase64LengthForBytes(4), 8);
    });
  });
}

Uint8List _solidPng({
  required int width,
  required int height,
  required img.Color color,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: color);
  return Uint8List.fromList(img.encodePng(image));
}
