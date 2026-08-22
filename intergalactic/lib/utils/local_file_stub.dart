import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<bool> localFileExists(String path) async {
  return true;
}

Future<Uint8List?> readLocalFileBytes(String path) async {
  return null;
}

Future<Uint8List?> readLocalFileBytesWithinLimit(
  String path, {
  required int maxBytes,
}) async {
  return null;
}

Future<Uint8List?> readLocalFileHeader(String path, {int maxBytes = 32}) async {
  return null;
}

Future<Uint8List?> readBytesFromUri(Uri uri) async {
  return null;
}

Future<Uri?> getLocalFileUri(String path) async {
  return Uri.tryParse(path);
}

Future<void> writeLocalFileBytes(String path, Uint8List bytes) async {}

ImageProvider buildLocalFileImage(String path) {
  return NetworkImage(path);
}

ImageProvider buildImageFromUri(Uri uri) {
  return NetworkImage(uri.toString());
}
