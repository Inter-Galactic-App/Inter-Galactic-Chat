import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<bool> localFileExists(String path) async {
  return File(path).exists();
}

Future<Uint8List?> readLocalFileBytes(String path) async {
  return File(path).readAsBytes();
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
