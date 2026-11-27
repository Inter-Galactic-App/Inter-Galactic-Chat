import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

Uint8List? decodePreferenceImageData(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  final separator = value.indexOf(',');
  final encoded = separator >= 0 ? value.substring(separator + 1) : value;

  try {
    return base64Decode(encoded);
  } catch (_) {
    return null;
  }
}

String encodePreferenceImageData(
  Uint8List bytes, {
  int? maxWidth,
  int? maxHeight,
}) {
  return base64Encode(
    _resizePreferenceImageData(
      bytes,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    ),
  );
}

Uint8List _resizePreferenceImageData(
  Uint8List bytes, {
  int? maxWidth,
  int? maxHeight,
}) {
  if ((maxWidth == null || maxWidth <= 0) &&
      (maxHeight == null || maxHeight <= 0)) {
    return bytes;
  }

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return bytes;
  }

  final widthLimit = maxWidth != null && maxWidth > 0
      ? maxWidth / decoded.width
      : double.infinity;
  final heightLimit = maxHeight != null && maxHeight > 0
      ? maxHeight / decoded.height
      : double.infinity;
  final scale = widthLimit < heightLimit ? widthLimit : heightLimit;
  if (scale >= 1 || !scale.isFinite || scale <= 0) {
    return bytes;
  }

  final resizedWidth =
      (decoded.width * scale).round().clamp(1, maxWidth ?? decoded.width);
  final resizedHeight =
      (decoded.height * scale).round().clamp(1, maxHeight ?? decoded.height);

  final resized = img.copyResize(
    decoded,
    width: resizedWidth.toInt(),
    height: resizedHeight.toInt(),
    interpolation: img.Interpolation.average,
  );

  return Uint8List.fromList(img.encodePng(resized));
}
