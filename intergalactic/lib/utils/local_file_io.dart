import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<bool> localFileExists(String path) async {
  return File(path).exists();
}

Future<Uint8List?> readLocalFileBytes(String path) async {
  return File(path).readAsBytes();
}

/// Reads a local file only when its encoded byte length stays below [maxBytes].
///
/// The stream end keeps a file that grows after the initial stat from being
/// materialized without a bound. Callers receive `null` for an oversized file
/// and can retain the original attachment instead.
Future<Uint8List?> readLocalFileBytesWithinLimit(
  String path, {
  required int maxBytes,
}) async {
  final file = File(path);
  if (await file.length() >= maxBytes) {
    return null;
  }

  final output = BytesBuilder(copy: false);
  await for (final chunk in file.openRead(0, maxBytes)) {
    output.add(chunk);
  }

  if (await file.length() >= maxBytes || output.length >= maxBytes) {
    return null;
  }

  return output.takeBytes();
}

/// Reads only a small prefix for content-type detection.
Future<Uint8List?> readLocalFileHeader(String path, {int maxBytes = 32}) async {
  final output = BytesBuilder(copy: false);
  try {
    await for (final chunk in File(path).openRead(0, maxBytes)) {
      output.add(chunk);
    }
    return output.takeBytes();
  } on FileSystemException {
    return null;
  }
}

Future<Uint8List?> readBytesFromUri(Uri uri) async {
  if (uri.scheme == 'file' || uri.scheme.isEmpty) {
    return File.fromUri(uri).readAsBytes();
  }

  return null;
}

Future<Uri?> getLocalFileUri(String path) async {
  return File(path).uri;
}

Future<void> writeLocalFileBytes(String path, Uint8List bytes) async {
  final file = File(path);
  await file.create(recursive: true);
  await file.writeAsBytes(bytes);
}

ImageProvider buildLocalFileImage(String path) {
  return Image.file(File(path)).image;
}

ImageProvider buildImageFromUri(Uri uri) {
  return Image.file(File.fromUri(uri)).image;
}
